// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

enum ReasoningCatalog {
    typealias Effort = LLMSettings.ReasoningEffort

    static let standard: [Effort] = [.none, .low, .medium, .high]

    static func efforts(for provider: Provider, model: String) -> [Effort] {
        guard provider.supportsReasoningEffort || provider.adapter != .openAICompatible else {
            return []
        }

        switch provider.adapter {
        case .system:
            return []
        case .anthropic, .gemini:
            return standard
        case .openAIResponses, .openAICompatible:
            return openAI(model: model)
        }
    }

    static func resolve(_ effort: Effort, for provider: Provider, model: String) -> Effort {
        let offered = efforts(for: provider, model: model)
        guard !offered.isEmpty else { return effort }
        guard !offered.contains(effort) else { return effort }

        let wanted = Effort.allCases.firstIndex(of: effort) ?? 0
        return offered.min { first, second in
            let a = abs((Effort.allCases.firstIndex(of: first) ?? 0) - wanted)
            let b = abs((Effort.allCases.firstIndex(of: second) ?? 0) - wanted)
            return a == b ? first.rawValue < second.rawValue : a < b
        } ?? offered[0]
    }

    private static func openAI(model: String) -> [Effort] {
        let id = model.lowercased()
        guard id.hasPrefix("gpt-5") || id.hasPrefix("o1") || id.hasPrefix("o3") || id.hasPrefix("o4") else {
            return standard
        }
        if id.hasSuffix("-pro") {
            return [.high]
        }
        if id.hasPrefix("o") {
            return [.low, .medium, .high]
        }
        if id.hasPrefix("gpt-5-") || id == "gpt-5" {
            return [.minimal, .low, .medium, .high]
        }
        return standard
    }
}
