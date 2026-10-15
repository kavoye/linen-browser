// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct ContextBreakdown: Codable, Equatable, Sendable {
    enum Category: String, Codable, CaseIterable, Sendable {
        case messages, toolActivity, availableTools, instructions, reasoning, images
    }

    var tokens: [Category: Int] = [:]
    var reservedTokens = 0

    var total: Int {
        tokens.values.reduce(0, +)
    }

    func scaled(to target: Int) -> [(category: Category, tokens: Int)] {
        let sum = total
        guard sum > 0, target > 0 else { return [] }
        return Category.allCases
            .map { ($0, Int((Double(tokens[$0, default: 0]) * Double(target) / Double(sum)).rounded())) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
    }
}
