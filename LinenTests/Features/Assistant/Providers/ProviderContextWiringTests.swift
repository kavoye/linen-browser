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

        #expect(budget.windowTokens == SystemModelWindow.tokens)
        #expect(budget.responseTokens <= budget.windowTokens / 4)
        #expect(budget.inputTokens + budget.responseTokens < budget.windowTokens)
        #expect(subject.defersTools)
        #expect(budget.toolOutput.controlLimit == 12)
    }

    @Test(arguments: [
        LLMSettings.ReasoningEffort.none,
        .low,
        .medium,
        .high,
    ])
    func onDeviceFitsAFirstMessage(effort: LLMSettings.ReasoningEffort) throws {
        let subject = try #require(agent(for: ProviderCatalog.appleOnDevice, effort: effort))
        let session = subject.makeSession()
        #expect(!subject.isOverBudget(session, nativeState: nil, promptCharacters: "hello".count))
    }

    @Test func onDeviceLoadsToolsOnDemandWithinItsBudget() throws {
        let subject = try #require(agent(for: ProviderCatalog.appleOnDevice, effort: .low))
        let offered = AgentToolCatalog.defaultIDs.sorted()
        let everything = Transcript(entries: Array(subject.makeSession().transcript) + Array(try LoadToolsToolTests.loading(offered)))
        func definitions(_ session: LanguageModelSession) -> [String] {
            session.transcript.flatMap { entry -> [String] in
                guard case .instructions(let value) = entry else { return [] }
                return value.toolDefinitions.map(\.name)
            }
        }
        let first = definitions(subject.makeSession())
        let loaded = definitions(subject.makeSession(transcript: everything))

        #expect(subject.budget.responseTokens <= 512)
        #expect(first.contains(LoadToolsTool.toolName))
        #expect(first.contains("readPage"))
        #expect(!first.contains("clickOnPage"))
        #expect(loaded.count > first.count)
        #expect(subject.toolSchemaTokens(for: everything) <= subject.budget.toolSchemaTokens)
    }

    @Test func onDeviceLoadsAPagesControlToolsWithinItsBudget() throws {
        let subject = try #require(agent(for: ProviderCatalog.appleOnDevice, effort: .low))
        let page = LoadToolsToolTests.reading("""
            CONTROLS:
            [1] field "Name" = (empty)
            [2] field "Photo" (file)
            [3] checkbox "Gift wrap" (unchecked)
            [4] scrollarea "List"
            [5] select "Size" = "Small" (options: Small | Large)
            [6] button "Add to cart"
            """)
        let loaded = subject.tools(for: page).map(\.name)

        #expect(loaded.contains("selectOption"))
        #expect(loaded.contains("clickOnPage"))
        #expect(subject.toolSchemaTokens(for: page) <= subject.budget.toolSchemaTokens)
    }

    @Test func onDeviceKeepsTheToolTheRequestNamesAfterReadingAPage() throws {
        let subject = try #require(agent(for: ProviderCatalog.appleOnDevice, effort: .low))
        let request = Transcript.Entry.prompt(.init(segments: [.text(.init(content: "A pop-up is covering this page. Close it by pressing the Escape key."))]))
        let page = Array(LoadToolsToolTests.reading("""
            CONTROLS:
            [1] link "Home" → http://127.0.0.1/
            [2] link "Lamps" → http://127.0.0.1/lamps
            [5] field "Email" (email) = (empty)
            [6] button "Subscribe"
            [7] select "Size" = "Small" (options: Small | Large)
            [8] checkbox "Gift wrap" (unchecked)
            """))
        let transcript = Transcript(entries: [request] + page + page)

        #expect(subject.tools(for: transcript).map(\.name).contains("pressKey"))
        #expect(subject.toolSchemaTokens(for: transcript) <= subject.budget.toolSchemaTokens)
    }

    @Test func aHostedProviderKeepsTheFullProfile() throws {
        let subject = try #require(agent(for: ProviderCatalog.openAI, effort: .low))
        let budget = subject.budget

        #expect(budget.windowTokens >= 128_000)
        #expect(budget.toolOutput == .standard)
    }

    @Test func theBudgetFollowsTheToolCount() {
        let window = 4_096
        let core = ContextBudget.resolve(
            windowTokens: window,
            desiredResponseTokens: 700,
            toolCount: 10
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
