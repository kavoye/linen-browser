// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct LyricsMatch: Identifiable, Equatable, Sendable {
    let id: Int
    let track: String
    let artist: String
    let album: String
    let duration: Double
    let synced: String
    let plain: String
    let isInstrumental: Bool

    /// What sets one entry apart from the next in the match menu: two uploads of
    /// the same song differ by album and by length, not by title.
    var label: String {
        var parts = [track.isEmpty ? artist : track]
        if !album.isEmpty, album != track {
            parts.append(album)
        }
        if duration > 0 {
            let whole = Int(duration.rounded())
            parts.append(String(format: "%d:%02d", whole / 60, whole % 60))
        }
        return parts.joined(separator: " · ")
    }

    /// Entries carrying the same words are the same entry as far as the reader
    /// is concerned, whatever the library calls them.
    var wordsKey: String {
        let words = synced.isEmpty ? plain : synced
        return words.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasWords: Bool {
        !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func track(matching duration: Double) -> LyricsTrack {
        let length = duration > 0 ? duration : self.duration
        return LyricsTrack(
            title: track,
            artist: artist,
            album: album,
            duration: length,
            lines: LyricsParser.lines(fromLRC: synced, duration: length),
            plainText: plain
        )
    }
}

nonisolated struct LyricsFetch: Sendable {
    var best: LyricsMatch?
    var alternatives: [LyricsMatch]
}

nonisolated protocol LyricsSource: Sendable {
    func lyrics(for queries: [LyricsQuery]) async -> LyricsFetch
    func alternatives(for query: LyricsQuery) async -> [LyricsMatch]
}

nonisolated struct LRCLIB: LyricsSource {
    static let home = URL(string: "https://lrclib.net")!
    static let alternativeLimit = 8

    var session: URLSession = .shared

    func lyrics(for queries: [LyricsQuery]) async -> LyricsFetch {
        for query in queries where query.isNamed {
            if let match = await exact(query), match.hasWords {
                return LyricsFetch(best: match, alternatives: [])
            }
        }

        for query in queries {
            let found = await search(query)
            guard !found.isEmpty else { continue }
            return LyricsFetch(best: found.first, alternatives: found)
        }
        return LyricsFetch(best: nil, alternatives: [])
    }

    func alternatives(for query: LyricsQuery) async -> [LyricsMatch] {
        await search(query)
    }

    // MARK: - Endpoints

    private func exact(_ query: LyricsQuery) async -> LyricsMatch? {
        var items = [
            URLQueryItem(name: "track_name", value: query.track),
            URLQueryItem(name: "artist_name", value: query.artist),
        ]
        if !query.album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: query.album))
        }
        if query.duration > 0 {
            items.append(URLQueryItem(name: "duration", value: String(Int(query.duration.rounded()))))
        }
        guard let data = await get(path: "/api/get", items: items) else { return nil }
        return Self.match(in: data)
    }

    private func search(_ query: LyricsQuery) async -> [LyricsMatch] {
        var items: [URLQueryItem] = []
        if query.isNamed {
            items = [
                URLQueryItem(name: "track_name", value: query.track),
                URLQueryItem(name: "artist_name", value: query.artist),
            ]
        } else {
            items = [URLQueryItem(name: "q", value: "\(query.track) \(query.artist)".trimmingCharacters(in: .whitespaces))]
        }
        guard let data = await get(path: "/api/search", items: items) else { return [] }
        return Self.ranked(in: data, against: query)
    }

    private func get(path: String, items: [URLQueryItem]) async -> Data? {
        var components = URLComponents(url: Self.home.appending(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = items
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return data
    }

    static var userAgent: String {
        "Linen/\(UpdateFeed.currentVersion) (https://github.com/\(UpdateFeed.owner)/\(UpdateFeed.repository))"
    }

    // MARK: - Decoding

    private struct Row: Decodable {
        let id: Int
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    static func match(in data: Data) -> LyricsMatch? {
        guard let row = try? JSONDecoder().decode(Row.self, from: data) else { return nil }
        return match(from: row)
    }

    static func ranked(in data: Data, against query: LyricsQuery) -> [LyricsMatch] {
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { return [] }

        let scored: [(match: LyricsMatch, score: Double)] = rows.compactMap { row in
            let found = match(from: row)
            guard found.hasWords,
                  let score = LyricsNaming.score(
                      track: found.track,
                      artist: found.artist,
                      duration: found.duration,
                      against: query
                  )
            else { return nil }
            return (found, score + (found.synced.isEmpty ? 0 : 0.75))
        }

        var seen: Set<String> = []
        return scored
            .sorted { $0.score > $1.score }
            .map(\.match)
            .filter { seen.insert($0.wordsKey).inserted }
            .prefix(alternativeLimit)
            .map { $0 }
    }

    private static func match(from row: Row) -> LyricsMatch {
        LyricsMatch(
            id: row.id,
            track: row.trackName ?? "",
            artist: row.artistName ?? "",
            album: row.albumName ?? "",
            duration: row.duration ?? 0,
            synced: row.syncedLyrics ?? "",
            plain: row.plainLyrics ?? "",
            isInstrumental: row.instrumental ?? false
        )
    }
}
