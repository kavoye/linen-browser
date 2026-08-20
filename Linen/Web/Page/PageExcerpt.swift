// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum PageExcerpt {
    static func extract(from text: String, query: String, budget: Int) -> String {
        guard budget > 0 else { return "" }
        guard text.count > budget else { return text }

        let terms = self.terms(in: query)
        guard !terms.isEmpty else { return prefix(text, budget) }

        let lowered = text.lowercased()
        let positions = matchPositions(of: terms, in: lowered)
        guard !positions.isEmpty else { return prefix(text, budget) }

        let anchor = bestClusterStart(positions: positions, span: budget)
        let start = max(0, anchor - budget / 3)
        return window(text, from: start, budget: budget)
    }

    static func terms(in query: String) -> [String] {
        query
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
    }

    // MARK: - Scoring

    private static func matchPositions(of terms: [String], in lowered: String) -> [Int] {
        var positions: [Int] = []
        for term in terms {
            var search = lowered.startIndex
            while let range = lowered.range(of: term, range: search..<lowered.endIndex) {
                positions.append(lowered.distance(from: lowered.startIndex, to: range.lowerBound))
                search = range.upperBound
            }
        }
        return positions.sorted()
    }

    private static func bestClusterStart(positions: [Int], span: Int) -> Int {
        var best = positions[0]
        var bestCount = 0
        var upper = 0
        for lower in positions.indices {
            if upper < lower {
                upper = lower
            }
            while upper + 1 < positions.count, positions[upper + 1] - positions[lower] < span {
                upper += 1
            }
            let count = upper - lower + 1
            if count > bestCount {
                bestCount = count
                best = positions[lower]
            }
        }
        return best
    }

    // MARK: - Cutting

    private static func prefix(_ text: String, _ budget: Int) -> String {
        guard text.count > budget else { return text }
        return String(text.prefix(budget)) + " …"
    }

    private static func window(_ text: String, from start: Int, budget: Int) -> String {
        let clampedStart = min(start, max(0, text.count - budget))
        let lower = text.index(text.startIndex, offsetBy: clampedStart)
        let upper = text.index(lower, offsetBy: min(budget, text.distance(from: lower, to: text.endIndex)))

        var slice = text[lower..<upper]
        if lower > text.startIndex, let firstSpace = slice.firstIndex(of: " ") {
            slice = slice[slice.index(after: firstSpace)...]
        }
        if upper < text.endIndex, let lastSpace = slice.lastIndex(of: " ") {
            slice = slice[..<lastSpace]
        }

        var result = String(slice)
        if lower > text.startIndex {
            result = "… " + result
        }
        if upper < text.endIndex {
            result += " …"
        }
        return result
    }
}
