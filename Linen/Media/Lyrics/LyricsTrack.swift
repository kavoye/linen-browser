// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct LyricsWord: Equatable, Sendable {
    let text: String
    let start: Double
    let end: Double
}

nonisolated struct LyricsLine: Identifiable, Equatable, Sendable {
    let id: Int
    let start: Double
    let end: Double
    let text: String
    let words: [LyricsWord]

    var isGap: Bool {
        text.isEmpty
    }

    var duration: Double {
        max(end - start, 0)
    }
}

nonisolated struct LyricsTrack: Equatable, Sendable {
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let lines: [LyricsLine]
    let plainText: String

    var isSynced: Bool {
        !lines.isEmpty
    }
}

nonisolated enum LyricsParser {
    static let shortestGap: Double = 3
    static let openingGap: Double = 5
    static let longestHold: Double = 8

    static func lines(fromLRC source: String, duration: Double) -> [LyricsLine] {
        var stamped: [(time: Double, text: String)] = []
        var shift: Double = 0

        for row in source.split(whereSeparator: \.isNewline) {
            var rest = Substring(row)
            var times: [Double] = []

            while rest.hasPrefix("[") {
                guard let close = rest.firstIndex(of: "]") else { break }
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                rest = rest[rest.index(after: close)...]
                if let seconds = seconds(inTimestamp: tag) {
                    times.append(seconds)
                } else if let found = offset(inTag: tag) {
                    shift = found
                }
            }

            guard !times.isEmpty else { continue }
            let text = clean(String(rest))
            for time in times {
                stamped.append((time, text))
            }
        }

        guard !stamped.isEmpty else { return [] }
        stamped.sort { $0.time < $1.time }

        var shifted = stamped.map { (time: max($0.time - shift, 0), text: $0.text) }
        if let first = shifted.first, !first.text.isEmpty, first.time >= openingGap {
            shifted.insert((time: 0, text: ""), at: 0)
        }

        var kept: [(time: Double, text: String)] = []
        for (index, row) in shifted.enumerated() {
            let next = index + 1 < shifted.count ? shifted[index + 1].time : duration
            let span = next > row.time ? next - row.time : .greatestFiniteMagnitude
            if row.text.isEmpty, span < shortestGap {
                continue
            }
            if let last = kept.last, last.text == row.text, last.text.isEmpty {
                continue
            }
            kept.append(row)
        }

        return kept.enumerated().map { index, row in
            let next = index + 1 < kept.count ? kept[index + 1].time : max(duration, row.time + 4)
            let end = max(next, row.time)
            return LyricsLine(
                id: index,
                start: row.time,
                end: end,
                text: row.text,
                words: words(in: row.text, from: row.time, before: end)
            )
        }
    }

    static func words(in text: String, from start: Double, before end: Double) -> [LyricsWord] {
        let tokens = text.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return [] }

        let room = max(end - start, 0.001)
        let natural = 0.3 * Double(tokens.count) + 0.035 * Double(text.count)
        let span = min(room, max(natural, min(room, 0.8)))
        let weights = tokens.map { Double($0.count) + 1 }
        let total = weights.reduce(0, +)

        var cursor = start
        var built: [LyricsWord] = []
        built.reserveCapacity(tokens.count)
        for (token, weight) in zip(tokens, weights) {
            let next = cursor + span * (weight / total)
            built.append(LyricsWord(text: token, start: cursor, end: next))
            cursor = next
        }
        return built
    }

    static func index(at time: Double, in lines: [LyricsLine]) -> Int? {
        guard let first = lines.first, time >= first.start else { return nil }

        var low = 0
        var high = lines.count - 1
        var found = 0
        while low <= high {
            let middle = (low + high) / 2
            if lines[middle].start <= time {
                found = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return found
    }

    private static func seconds(inTimestamp tag: Substring) -> Double? {
        let parts = tag.split(separator: ":")
        guard parts.count == 2,
              let minutes = Int(parts[0]),
              minutes >= 0,
              let seconds = Double(parts[1].replacingOccurrences(of: ",", with: ".")),
              seconds >= 0, seconds < 60
        else { return nil }
        return Double(minutes) * 60 + seconds
    }

    private static func offset(inTag tag: Substring) -> Double? {
        let parts = tag.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, parts[0].lowercased() == "offset",
              let milliseconds = Double(parts[1].trimmingCharacters(in: .whitespaces))
        else { return nil }
        return milliseconds / 1000
    }

    private static func clean(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed == "♪" || trimmed == "..." ? "" : trimmed
    }
}
