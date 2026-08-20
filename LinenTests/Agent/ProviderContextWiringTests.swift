// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import Testing

@testable import Linen

@MainActor
struct ProviderContextWiringTests {
    private func agent(
        for provider: Provider,
        effort: LLMSettings.ReasoningEffort
    ) -> AnyLanguageModelAgent? {
        let log = ConversationLog(database: .temporary())
        let built = ModelProviderRegistry().resolve(provider).makeAgent(
            model: LLMSettings.model(for: provider),
            reasoningEffort: effort,
            toolkit: AgentToolkit(
                browser: BrowserModel(database: .temporary()),
                media: MediaCenter(),
                log: log
            ),
            log: log
        )
        return built as? AnyLanguageModelAgent
    }

    @Test(arguments: [
        LLMSettings.ReasoningEffort.none,
        .low,
        .medium,
        .high,
    ])
    func onDeviceNeverReservesMoreThanItsWindowAllows(
        effort: LLMSettings.ReasoningEffort
    ) throws {
        let subject = try #require(agent(for: ProviderCatalog.appleOnDevice, effort: effort))
        let budget = subject.budget

        #expect(budget.windowTokens == 4_096)
        #expect(budget.responseTokens <= budget.windowTokens / 4)
        #expect(budget.inputTokens + budget.responseTokens < budget.windowTokens)
        #expect(budget.instructionTier == .compact)
        #expect(budget.toolTier == .core)
        #expect(budget.toolOutput.controlLimit == 12)
    }

    @Test func aHostedProviderKeepsTheFullProfile() throws {
        let subject = try #require(agent(for: ProviderCatalog.openAI, effort: .low))
        let budget = subject.budget

        #expect(budget.windowTokens >= 128_000)
        #expect(budget.instructionTier == .full)
        #expect(budget.toolTier == .full)
        #expect(budget.toolOutput == .standard)
        #expect(budget.maxToolCalls == 20)
    }

    @Test func theBudgetFollowsTheToolCount() {
        let window = 4_096
        let core = ContextBudget.resolve(
            windowTokens: window,
            desiredResponseTokens: 700,
            toolCount: AgentToolCatalog.defaultIDs(for: .core).count
        )
        let everything = ContextBudget.resolve(
            windowTokens: window,
            desiredResponseTokens: 700,
            toolCount: AgentToolCatalog.all.count
        )

        #expect(core.toolSchemaTokens < everything.toolSchemaTokens)
        #expect(core.toolOutput.pageTextCharacters >= everything.toolOutput.pageTextCharacters)
    }
}
