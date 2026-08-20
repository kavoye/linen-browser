// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation
import os

nonisolated struct GitHubRelease: Decodable, Equatable, Sendable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let publishedAt: Date?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
    }

    var displayTitle: String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return name
        }
        return tagName
    }
}

@MainActor
@Observable
final class ReleaseNotesModel {
    private static let seenKey = "updates.notesSeenVersion"

    private(set) var release: GitHubRelease?
    var isPresented = false

    private var hasAttempted = false

    func presentIfNewVersion() async {
        guard !hasAttempted else { return }
        hasAttempted = true

        let current = UpdateFeed.currentVersion
        let defaults = UserDefaults.standard
        guard let seen = defaults.string(forKey: Self.seenKey) else {
            defaults.set(current, forKey: Self.seenKey)
            return
        }
        guard seen != current else { return }

        guard let release = await Self.fetchRelease(version: current) else {
            Pipeline.log.notice("release notes: none published for \(current, privacy: .public) yet")
            return
        }

        self.release = release
        isPresented = true
        defaults.set(current, forKey: Self.seenKey)
    }

    func dismiss() {
        isPresented = false
    }

    private static func fetchRelease(version: String) async -> GitHubRelease? {
        for tag in ["v\(version)", version] {
            if let release = await fetch(tag: tag) {
                return release
            }
        }
        return nil
    }

    private static func fetch(tag: String) async -> GitHubRelease? {
        var request = URLRequest(url: UpdateFeed.releaseAPI(tag: tag))
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(GitHubRelease.self, from: data)
        } catch {
            Pipeline.log.error("release notes: fetch failed - \(error, privacy: .public)")
            return nil
        }
    }
}
