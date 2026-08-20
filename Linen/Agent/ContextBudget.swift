// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct ContextBudget: Hashable, Sendable {
    nonisolated struct ToolOutputBudget: Hashable, Sendable {
        var pageTextCharacters: Int
        var controlLimit: Int

        static let standard = Self(pageTextCharacters: 2_400, controlLimit: 40)
    }

    let windowTokens: Int
    let responseTokens: Int
    let inputTokens: Int
    let toolSchemaTokens: Int
    let instructionTier: AgentInstructions.Tier
    let toolTier: AgentToolTier
    let toolOutput: ToolOutputBudget
    let maxToolCalls: Int
    let retainedExchanges: Int
    let retainedToolRounds: Int

    static func toolTier(forWindow windowTokens: Int) -> AgentToolTier {
        windowTokens < 16_384 ? .core : .full
    }

    static func resolve(
        windowTokens: Int,
        desiredResponseTokens: Int,
        toolCount: Int? = nil
    ) -> Self {
        let window = max(2_048, windowTokens)
        let response = max(256, min(desiredResponseTokens, window / 4))
        let safety = max(256, window / 16)
        let input = window - response - safety
        let compact = window < 16_384

        let instructionTokens = compact ? 300 : 1_300
        let schemaTokens = toolCount.map { max(150, $0 * 75) } ?? (compact ? 500 : 1_200)
        let conversation = max(512, input - instructionTokens - schemaTokens)

        let output: ToolOutputBudget
        if compact {
            let outputTokens = max(300, min(conversation / 3, 650))
            output = ToolOutputBudget(
                pageTextCharacters: max(800, min((outputTokens - 200) * 4, 1_600)),
                controlLimit: 12
            )
        } else {
            output = .standard
        }

        return Self(
            windowTokens: window,
            responseTokens: response,
            inputTokens: input,
            toolSchemaTokens: schemaTokens,
            instructionTier: compact ? .compact : .full,
            toolTier: compact ? .core : .full,
            toolOutput: output,
            maxToolCalls: compact ? max(3, min(8, conversation / 300)) : 20,
            retainedExchanges: compact ? max(1, min(4, conversation / 800)) : 12,
            retainedToolRounds: compact ? 1 : 3
        )
    }
}

nonisolated enum ContextWindow {
    static func tokens(for provider: Provider, model: String) -> Int {
        if let override = LLMSettings.contextWindow(for: provider) {
            return override
        }
        if let discovered = LLMSettings.discoveredContextWindow(for: provider, model: model) {
            return discovered
        }
        return switch provider.adapter {
        case .system:
            4_096
        case .anthropic:
            200_000
        case .gemini:
            1_000_000
        case .openAIResponses:
            400_000
        case .openAICompatible:
            provider.isLocal ? 4_096 : 128_000
        }
    }
}

nonisolated extension LLMSettings {
    private static func contextWindowKey(for provider: Provider) -> String {
        "llm.contextWindow.\(provider.id)"
    }

    static func contextWindow(for provider: Provider) -> Int? {
        let stored = defaults.integer(forKey: contextWindowKey(for: provider))
        return stored > 0 ? stored : nil
    }

    static func setContextWindow(_ tokens: Int?, for provider: Provider) {
        if let tokens, tokens > 0 {
            defaults.set(tokens, forKey: contextWindowKey(for: provider))
        } else {
            defaults.removeObject(forKey: contextWindowKey(for: provider))
        }
    }
}
