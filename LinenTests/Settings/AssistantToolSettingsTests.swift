// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@MainActor
@Suite(.serialized)
struct AssistantToolSettingsTests {
    private static let inUse = Provider(
        id: "in-use",
        name: "In Use",
        blurb: "",
        symbol: "circle",
        baseURL: URL(string: "https://models.example/v1"),
        wire: .chatCompletions,
        auth: .none,
        defaultModel: "big-model"
    )

    private static let other = Provider(
        id: "other",
        name: "Other",
        blurb: "",
        symbol: "circle",
        baseURL: URL(string: "http://localhost:11434/v1"),
        wire: .chatCompletions,
        auth: .none,
        isLocal: true,
        defaultModel: "small-model"
    )

    private func makeModel(onChange: @escaping () -> Void) -> (IntelligenceViewModel, TestProviderCatalog) {
        let catalog = TestProviderCatalog(providers: [Self.inUse, Self.other], selectedID: Self.inUse.id)
        let credentials = TestCredentialStore()
        let model = IntelligenceViewModel(
            catalog: catalog,
            credentials: credentials,
            modelProviders: ModelProviderRegistry(credentials: credentials),
            contextProbe: SilentContextProbe(),
            onConfigurationChanged: onChange
        )
        return (model, catalog)
    }

    private func withCleanDefaults(_ body: (IntelligenceViewModel, @escaping () -> Int) -> Void) {
        let previous = LLMSettings.defaults
        let suiteName = "assistant-tool-settings-tests"
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.removePersistentDomain(forName: suiteName)
        LLMSettings.defaults = defaults ?? .standard
        defer { LLMSettings.defaults = previous }

        var changes = 0
        let (model, _) = makeModel { changes += 1 }
        body(model, { changes })
    }

    @Test func toolsBelongToTheProviderOnScreen() {
        withCleanDefaults { model, _ in
            #expect(model.subject.id == Self.inUse.id)
            #expect(model.enabledTools == AgentToolCatalog.defaultIDs(for: .full))

            model.open(Self.other)

            #expect(model.subject.id == Self.other.id)
            #expect(model.enabledTools == AgentToolCatalog.defaultIDs(for: .core))
        }
    }

    @Test func editingAnotherProviderLeavesTheOneInUseAlone() {
        withCleanDefaults { model, _ in
            model.open(Self.other)
            model.setTool("playVideo", enabled: true)

            #expect(LLMSettings.enabledAgentTools(for: Self.other)?.contains("playVideo") == true)
            #expect(LLMSettings.enabledAgentTools(for: Self.inUse) == nil)

            model.showOverview()
            #expect(model.enabledTools == AgentToolCatalog.defaultIDs(for: .full))
        }
    }

    @Test func onlyEditsToTheProviderInUseRebuildTheAgent() {
        withCleanDefaults { model, changes in
            model.open(Self.other)
            model.setTool("playVideo", enabled: true)
            #expect(changes() == 0, "editing an idle provider rebuilt the running agent")

            model.showOverview()
            model.setTool("playVideo", enabled: false)
            #expect(changes() == 1, "editing the provider in use did not rebuild the agent")
        }
    }

    @Test func resetReturnsToTheRecommendedSetForThatProvider() {
        withCleanDefaults { model, _ in
            model.open(Self.other)
            model.setTool("playVideo", enabled: true)
            model.setTool("closeVideo", enabled: true)
            #expect(!model.isUsingRecommendedTools)
            #expect(model.toolWarning != nil)

            model.resetToolsToRecommended()

            #expect(model.isUsingRecommendedTools)
            #expect(model.toolWarning == nil)
            #expect(model.enabledTools == AgentToolCatalog.defaultIDs(for: .core))
            #expect(LLMSettings.enabledAgentTools(for: Self.other) == nil)
        }
    }

    @Test func aLargeWindowProviderNeverWarns() {
        withCleanDefaults { model, _ in
            model.setTool("playVideo", enabled: true)

            #expect(model.recommendedToolIDs == AgentToolCatalog.defaultIDs(for: .full))
            #expect(model.toolWarning == nil)
        }
    }

    @Test func leavingToolsReturnsToTheProviderItWasOpenedFrom() {
        withCleanDefaults { model, _ in
            model.open(Self.other)
            model.showTools()
            #expect(model.destination == .tools)

            model.leaveTools()
            #expect(model.destination == .provider(Self.other.id))

            model.showOverview()
            model.showTools()
            model.leaveTools()
            #expect(model.destination == .overview)
        }
    }
}

nonisolated private struct SilentContextProbe: ContextWindowProbing {
    func effectiveWindow(for provider: Provider, model: String) async -> Int? {
        nil
    }
}

nonisolated private struct TestCredentialStore: ProviderCredentialStore {
    func key(for provider: Provider) -> String? {
        nil
    }
    func isConfigured(_ provider: Provider) -> Bool {
        true
    }
    func source(for provider: Provider) -> CredentialStore.Source {
        .none
    }
    func masked(for provider: Provider) -> String? {
        nil
    }
    func save(_ key: String, for provider: Provider) -> String? {
        nil
    }
    func delete(for provider: Provider) {}
}

@MainActor
private final class TestProviderCatalog: ProviderCatalogProtocol {
    private(set) var all: [Provider]
    private var selectedID: String

    init(providers: [Provider], selectedID: String) {
        all = providers
        self.selectedID = selectedID
    }

    var selected: Provider {
        provider(id: selectedID) ?? all.first ?? ProviderCatalog.openAI
    }

    func provider(id: String) -> Provider? {
        all.first { $0.id == id }
    }

    func select(_ provider: Provider) {
        selectedID = provider.id
    }

    func save(_ provider: Provider) {
        if let index = all.firstIndex(where: { $0.id == provider.id }) {
            all[index] = provider
        } else {
            all.append(provider)
        }
    }

    func remove(_ provider: Provider) {
        all.removeAll { $0.id == provider.id }
        if selectedID == provider.id {
            selectedID = all.first?.id ?? ProviderCatalog.openAI.id
        }
    }
}
