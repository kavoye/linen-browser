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

    @Test func anEnabledSetFiltersTheSessionToolsButNeverAsking() {
        let enabled: Set<String> = ["searchWeb", "readPage", "playVideo"]
        let names = makeAgentTools(toolkit: toolkit(), enabledIDs: enabled).map(\.name)

        #expect(names == ["askUser", "searchWeb", "readPage", "playVideo"])
    }

    @Test func everyModelGetsTheSameReadPage() throws {
        let readPage = try #require(makeAgentTools(toolkit: toolkit()).first { $0.name == "readPage" })
        let schema = try #require(String(data: try JSONEncoder().encode(readPage.parameters), encoding: .utf8))

        #expect(readPage.description == AgentToolkit.Descriptions.readPage)
        #expect(!schema.contains("viewportOnly"))
    }

    @Test func everyCategoryListsItsToolsInCatalogOrder() {
        let flattened = AgentToolDescriptor.Category.allCases.flatMap { category in
            AgentToolCatalog.descriptors(in: category).map(\.id)
        }

        #expect(Set(flattened) == AgentToolCatalog.configurableIDs)
        #expect(Set(flattened).isDisjoint(with: AgentToolCatalog.visualToolIDs))
    }
}

@Suite(.serialized)
struct AgentToolPreferencesTests {
    @Test func aStoredSelectionWinsOverTheDefault() {
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
            AgentToolCatalog.resolvedIDs(for: provider) == AgentToolCatalog.defaultIDs
        )

        let chosen: Set<String> = ["searchWeb", "readPage", "playVideo"]
        LLMSettings.setEnabledAgentTools(chosen, for: provider)
        #expect(AgentToolCatalog.resolvedIDs(for: provider) == chosen.union(AgentToolCatalog.visualToolIDs))

        LLMSettings.setEnabledAgentTools(["not-a-tool"], for: provider)
        #expect(
            AgentToolCatalog.resolvedIDs(for: provider) == AgentToolCatalog.defaultIDs
        )

        LLMSettings.setEnabledAgentTools(nil, for: provider)
        #expect(LLMSettings.enabledAgentTools(for: provider) == nil)
    }
}
