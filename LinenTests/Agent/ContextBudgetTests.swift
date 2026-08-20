// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

struct ContextBudgetTests {
    @Test func aTinyWindowGetsTheCompactProfile() {
        let budget = ContextBudget.resolve(windowTokens: 4_096, desiredResponseTokens: 2_000)

        #expect(budget.responseTokens == 1_024)
        #expect(budget.instructionTier == .compact)
        #expect(budget.toolTier == .core)
        #expect(budget.toolOutput.pageTextCharacters <= 1_600)
        #expect(budget.toolOutput.controlLimit == 12)
        #expect(budget.maxToolCalls <= 8)
        #expect(budget.retainedToolRounds == 1)
        #expect(budget.inputTokens + budget.responseTokens < budget.windowTokens)
    }

    @Test func aLargeRemoteWindowKeepsTheFullProfile() {
        let budget = ContextBudget.resolve(windowTokens: 200_000, desiredResponseTokens: 8_892)

        #expect(budget.responseTokens == 8_892)
        #expect(budget.instructionTier == .full)
        #expect(budget.toolTier == .full)
        #expect(budget.toolOutput == .standard)
        #expect(budget.maxToolCalls == 20)
        #expect(budget.retainedExchanges == 12)
    }

    @Test func theBudgetAlwaysLeavesRoomForInputAndAnswer() {
        let budget = ContextBudget.resolve(windowTokens: 2_048, desiredResponseTokens: 10_000)

        #expect(budget.responseTokens == 512)
        #expect(budget.inputTokens > 0)
        #expect(budget.toolOutput.pageTextCharacters >= 800)
        #expect(budget.maxToolCalls >= 3)
        #expect(budget.retainedExchanges >= 1)
    }

    @Test func theWindowTableCoversEveryAdapter() {
        #expect(ContextWindow.tokens(for: provider(adapter: .system), model: "") == 4_096)
        #expect(ContextWindow.tokens(for: provider(adapter: .anthropic), model: "") == 200_000)
        #expect(ContextWindow.tokens(for: provider(adapter: .gemini), model: "") == 1_000_000)
        #expect(ContextWindow.tokens(for: provider(adapter: .openAIResponses), model: "") == 400_000)
        #expect(ContextWindow.tokens(for: provider(adapter: .openAICompatible), model: "") == 128_000)
        #expect(
            ContextWindow.tokens(for: provider(adapter: .openAICompatible, isLocal: true), model: "")
                == 4_096
        )
    }

    @Test func theToolCountRefinesTheSchemaBudget() {
        let few = ContextBudget.resolve(windowTokens: 4_096, desiredResponseTokens: 2_000, toolCount: 7)
        let many = ContextBudget.resolve(windowTokens: 4_096, desiredResponseTokens: 2_000, toolCount: 14)

        #expect(few.toolSchemaTokens < many.toolSchemaTokens)
        #expect(few.toolOutput.pageTextCharacters >= many.toolOutput.pageTextCharacters)
    }

    @Test func theToolTierFollowsTheWindow() {
        #expect(ContextBudget.toolTier(forWindow: 4_096) == .core)
        #expect(ContextBudget.toolTier(forWindow: 128_000) == .full)
    }

    private func provider(adapter: Provider.Adapter, isLocal: Bool = false) -> Provider {
        Provider(
            id: "budget-test",
            name: "Budget Test",
            blurb: "",
            symbol: "circle",
            baseURL: URL(string: "http://localhost:1"),
            wire: .chatCompletions,
            adapter: adapter,
            auth: .none,
            isLocal: isLocal
        )
    }
}

@Suite(.serialized)
struct ContextWindowOverrideTests {
    @Test func aStoredOverrideWinsOverTheDefaultWindow() {
        let previous = LLMSettings.defaults
        let suiteName = "context-window-override-tests"
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.removePersistentDomain(forName: suiteName)
        LLMSettings.defaults = defaults ?? .standard
        defer { LLMSettings.defaults = previous }

        let local = Provider(
            id: "override-test",
            name: "Override Test",
            blurb: "",
            symbol: "circle",
            baseURL: URL(string: "http://localhost:1"),
            wire: .chatCompletions,
            auth: .none,
            isLocal: true
        )

        #expect(ContextWindow.tokens(for: local, model: "qwen3.5") == 4_096)

        LLMSettings.setDiscoveredContextWindow(16_384, for: local, model: "qwen3.5")
        #expect(ContextWindow.tokens(for: local, model: "qwen3.5") == 16_384)
        #expect(ContextWindow.tokens(for: local, model: "other-model") == 4_096)

        LLMSettings.setContextWindow(32_768, for: local)
        #expect(ContextWindow.tokens(for: local, model: "qwen3.5") == 32_768)
        #expect(
            ContextBudget.resolve(
                windowTokens: ContextWindow.tokens(for: local, model: "qwen3.5"),
                desiredResponseTokens: 2_000
            ).instructionTier == .full
        )

        LLMSettings.setContextWindow(nil, for: local)
        LLMSettings.setDiscoveredContextWindow(nil, for: local, model: "qwen3.5")
        #expect(ContextWindow.tokens(for: local, model: "qwen3.5") == 4_096)
    }
}
