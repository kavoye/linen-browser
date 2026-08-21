// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct LyricsQuery: Equatable, Hashable, Sendable {
    var track: String
    var artist: String
    var album: String
    var duration: Double

    var isUsable: Bool {
        !track.isEmpty
    }

    var isNamed: Bool {
        !track.isEmpty && !artist.isEmpty
    }
}

nonisolated enum LyricsNaming {
    static let separators: [String] = [" - ", " – ", " — ", " ‒ ", " ~ ", " | "]

    private static let noise: Set<String> = [
        "official", "officiel", "oficial", "video", "videoclip", "audio", "lyric", "lyrics",
        "letra", "visualizer", "visualiser", "hd", "hq", "uhd", "4k", "8k", "mv", "m/v",
        "remaster", "remastered", "remasterizado", "explicit", "clean", "colorcoded",
        "fullvideo", "musicvideo", "audioonly", "quality", "hdvideo",
    ]

    private static let channelMarkers: [String] = [
        " - topic", "vevo", " official", "officialmusic", " records", " music",
    ]

    static func queries(
        title rawTitle: String,
        artist rawArtist: String,
        album rawAlbum: String,
        duration: Double
    ) -> [LyricsQuery] {
        let title = cleanTitle(rawTitle)
        let artist = cleanArtist(rawArtist)
        let album = cleanTitle(rawAlbum)
        guard !title.isEmpty else { return [] }

        func query(_ track: String, _ performer: String, withAlbum: Bool) -> LyricsQuery {
            LyricsQuery(
                track: track,
                artist: performer,
                album: withAlbum ? album : "",
                duration: duration
            )
        }

        var built: [LyricsQuery] = []
        if let split = split(title) {
            let left = cleanArtist(split.left)
            let right = cleanTitle(split.right)
            if !right.isEmpty {
                if artist.isEmpty || matches(left, artist) {
                    built.append(query(right, artist.isEmpty ? left : artist, withAlbum: true))
                } else {
                    built.append(query(right, left, withAlbum: false))
                    built.append(query(right, artist, withAlbum: true))
                }
            }
        }
        built.append(query(title, artist, withAlbum: true))

        var seen: Set<LyricsQuery> = []
        return built.filter { $0.isUsable && seen.insert($0).inserted }
    }

    static func split(_ title: String) -> (left: String, right: String)? {
        for separator in separators {
            guard let range = title.range(of: separator) else { continue }
            let left = String(title[title.startIndex..<range.lowerBound])
            let right = String(title[range.upperBound...])
            guard !left.trimmed.isEmpty, !right.trimmed.isEmpty else {
                continue
            }
            return (left, right)
        }
        return nil
    }

    static func cleanTitle(_ raw: String) -> String {
        var text = ""
        var depth = 0
        var group = ""

        for character in raw {
            if character == "(" || character == "[" || character == "{" {
                if depth == 0 {
                    group = ""
                } else {
                    group.append(character)
                }
                depth += 1
                continue
            }
            if character == ")" || character == "]" || character == "}", depth > 0 {
                depth -= 1
                if depth == 0 {
                    if !isNoise(group) {
                        text.append("(\(group.trimmed))")
                    }
                } else {
                    group.append(character)
                }
                continue
            }
            if depth > 0 {
                group.append(character)
            } else {
                text.append(character)
            }
        }

        return tidy(text)
    }

    static func cleanArtist(_ raw: String) -> String {
        var text = cleanTitle(raw)
        var lowered = text.lowercased()
        for marker in channelMarkers where lowered.hasSuffix(marker) {
            text = String(text.dropLast(marker.count))
            lowered = text.lowercased()
        }
        if lowered.hasSuffix("vevo") {
            text = String(text.dropLast(4))
        }
        return tidy(text)
    }

    static func score(
        track: String,
        artist: String,
        duration: Double,
        against query: LyricsQuery
    ) -> Double? {
        let drift = query.duration > 0 && duration > 0 ? abs(duration - query.duration) : nil
        if let drift, drift > 20 {
            return nil
        }

        let title = overlap(track, query.track)
        guard title > 0 else { return nil }

        let performer = query.artist.isEmpty ? 0.5 : overlap(artist, query.artist)
        let timing = drift.map { max(0, 1 - $0 / 15) } ?? 0.35
        return title * 2 + performer + timing * 2
    }

    static func overlap(_ one: String, _ other: String) -> Double {
        let left = tokens(one)
        let right = tokens(other)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let shared = left.intersection(right).count
        return Double(shared) / Double(left.union(right).count)
    }

    static func tokens(_ text: String) -> Set<String> {
        Set(
            text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { $0.count > 1 || $0.first?.isNumber == true }
        )
    }

    private static func matches(_ one: String, _ other: String) -> Bool {
        !one.isEmpty && tokens(one) == tokens(other)
    }

    private static func isNoise(_ group: String) -> Bool {
        let words = group
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        guard !words.isEmpty else { return true }
        return words.contains { noise.contains($0) }
    }

    private static func tidy(_ text: String) -> String {
        var trimmed = text.trimmed
        while let last = trimmed.last, "-–—~|,:".contains(last) {
            trimmed = String(trimmed.dropLast()).trimmed
        }
        while let first = trimmed.first, "-–—~|,:".contains(first) {
            trimmed = String(trimmed.dropFirst()).trimmed
        }
        if trimmed.count > 2, let first = trimmed.first, let last = trimmed.last,
           "\"“'‘".contains(first), "\"”'’".contains(last) {
            trimmed = String(trimmed.dropFirst().dropLast()).trimmed
        }
        return trimmed.replacingOccurrences(of: "  ", with: " ")
    }
}

private extension String {
    nonisolated var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
