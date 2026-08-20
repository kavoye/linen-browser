// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

@MainActor
@Observable
final class SearchSuggestions {
    private(set) var phrases: [String] = []

    private var fetchTask: Task<Void, Never>?
    private var cache: [String: [String]] = [:]
    private var cacheOrder: [String] = []

    private static let limit = 6
    private static let cacheCapacity = 80

    func update(for raw: String) {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        fetchTask?.cancel()

        let engine = SearchURLBuilder.engine
        guard BrowserSettings.shared.showsSearchSuggestions,
              !Omnibox.isAgentOnly,
              engine.suggestTemplate != nil
        else {
            phrases = []
            return
        }

        guard query.count >= 2, !BrowserModel.looksLikeLocation(query) else {
            phrases = []
            return
        }

        if let hit = cache[Self.cacheKey(query, engine)] {
            phrases = hit
            return
        }

        fetchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            let fetched = await Self.fetch(query, from: engine)
            guard !Task.isCancelled else { return }
            self?.store(fetched, for: query, engine: engine)
        }
    }

    private static func cacheKey(_ query: String, _ engine: SearchEngine) -> String {
        "\(engine.id)\u{1}\(query.lowercased())"
    }

    func clear() {
        fetchTask?.cancel()
        fetchTask = nil
        phrases = []
    }

    private func store(_ fetched: [String], for query: String, engine: SearchEngine) {
        let kept = Array(
            fetched
                .filter { $0.caseInsensitiveCompare(query) != .orderedSame }
                .prefix(Self.limit)
        )
        let key = Self.cacheKey(query, engine)
        if cache.updateValue(kept, forKey: key) == nil {
            cacheOrder.append(key)
            if cacheOrder.count > Self.cacheCapacity {
                cache.removeValue(forKey: cacheOrder.removeFirst())
            }
        }
        phrases = kept
    }

    // MARK: - Network

    private struct Completion: Decodable {
        let phrase: String
    }

    nonisolated static func fetch(_ query: String, from engine: SearchEngine) async -> [String] {
        guard let url = engine.suggestURL(for: query) else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        request.cachePolicy = .returnCacheDataElseLoad

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return [] }

        return phrases(in: data, format: engine.suggestionFormat)
    }

    nonisolated static func phrases(in data: Data, format: SearchEngine.SuggestionFormat) -> [String] {
        switch format {
        case .phrases:
            let rows = try? JSONDecoder().decode([Completion].self, from: data)
            return rows?.map(\.phrase) ?? []
        case .openSearch:
            let parsed = try? JSONSerialization.jsonObject(with: data)
            guard let array = parsed as? [Any], array.count > 1 else { return [] }
            return (array[1] as? [String]) ?? []
        }
    }
}
