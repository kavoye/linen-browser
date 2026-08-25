// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import Testing

@testable import Linen

@MainActor
struct AgentToolCatalogTests {
    private func toolkit() -> AgentToolkit {
        AgentToolkit(
            browser: BrowserModel(database: .temporary()),
            media: MediaCenter(),
            log: ConversationLog(database: .temporary())
        )
    }

    @Test func theCatalogNamesEveryRegisteredToolBarAsking() {
        let registered = Set(makeAgentTools(toolkit: toolkit()).map(\.name))
        let described = Set(AgentToolCatalog.all.map(\.id))

        #expect(registered.subtracting([AskUserTool.toolName]) == described)
        #expect(!described.contains(AskUserTool.toolName))
        #expect(AgentToolCatalog.all.count == registered.count - 1)
    }

    @Test func theCoreDefaultsMatchTheCoreTier() {
        let coreTier = Set(makeAgentTools(toolkit: toolkit(), tier: .core).map(\.name))
            .subtracting([AskUserTool.toolName])

        #expect(AgentToolCatalog.defaultIDs(for: .core) == coreTier)
        #expect(AgentToolCatalog.defaultIDs(for: .full).count == AgentToolCatalog.all.count)
    }

    @Test func anEnabledSetFiltersTheSessionToolsButNeverAsking() {
        let enabled: Set<String> = ["searchWeb", "readPage", "playVideo"]
        let names = makeAgentTools(toolkit: toolkit(), enabledIDs: enabled).map(\.name)

        #expect(Set(names) == enabled.union([AskUserTool.toolName]))
        #expect(names == ["askUser", "searchWeb", "readPage", "playVideo"])
    }

    @Test func everyCategoryListsItsToolsInCatalogOrder() {
        let flattened = AgentToolDescriptor.Category.allCases.flatMap { category in
            AgentToolCatalog.descriptors(in: category).map(\.id)
        }

        #expect(Set(flattened) == Set(AgentToolCatalog.all.map(\.id)))
    }
}

@Suite(.serialized)
struct AgentToolPreferencesTests {
    @Test func aStoredSelectionWinsOverTheTierDefault() {
        let previous = LLMSettings.defaults
        let suiteName = "agent-tool-preferences-tests"
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.removePersistentDomain(forName: suiteName)
        LLMSettings.defaults = defaults ?? .standard
        defer { LLMSettings.defaults = previous }

        let provider = Provider(
            id: "tools-test",
            name: "Tools Test",
            blurb: "",
            symbol: "circle",
            baseURL: URL(string: "http://localhost:1"),
            wire: .chatCompletions,
            auth: .none,
            isLocal: true
        )

        #expect(LLMSettings.enabledAgentTools(for: provider) == nil)
        #expect(
            AgentToolCatalog.resolvedIDs(for: provider, tier: .core)
                == AgentToolCatalog.defaultIDs(for: .core)
        )

        let chosen: Set<String> = ["searchWeb", "readPage", "playVideo"]
        LLMSettings.setEnabledAgentTools(chosen, for: provider)
        #expect(AgentToolCatalog.resolvedIDs(for: provider, tier: .core) == chosen)

        LLMSettings.setEnabledAgentTools(["not-a-tool"], for: provider)
        #expect(
            AgentToolCatalog.resolvedIDs(for: provider, tier: .core)
                == AgentToolCatalog.defaultIDs(for: .core)
        )

        LLMSettings.setEnabledAgentTools(nil, for: provider)
        #expect(LLMSettings.enabledAgentTools(for: provider) == nil)
    }
}
