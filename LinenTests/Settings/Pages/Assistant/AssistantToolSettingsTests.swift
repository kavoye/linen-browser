// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@MainActor
@Suite(.serialized)
struct AssistantToolSettingsTests {
    @Test func profileModelChoicesAndToolSettingsRemainIndependent() throws {
        let firstName = TestDefaults.name("model-profile-first")
        let secondName = TestDefaults.name("model-profile-second")
        let firstDefaults = try #require(UserDefaults(suiteName: firstName))
        let secondDefaults = try #require(UserDefaults(suiteName: secondName))
        defer {
            firstDefaults.removePersistentDomain(forName: firstName)
            secondDefaults.removePersistentDomain(forName: secondName)
        }
        let first = LLMSettings(defaults: firstDefaults)
        let second = LLMSettings(defaults: secondDefaults)
        let provider = ProviderCatalog.openAI
        let otherProvider = try #require(ProviderCatalog.shared.provider(id: "anthropic"))
        first.providerID = provider.id
        second.providerID = otherProvider.id
        first.setModel("saved-first", for: provider)
        first.setReasoningEffort(.high, for: provider)
        let firstModel = IntelligenceViewModel(settings: first, credentials: TestCredentialStore(),
            contextProbe: SilentContextProbe(), onConfigurationChanged: {})
        let secondModel = IntelligenceViewModel(settings: second, credentials: TestCredentialStore(),
            contextProbe: SilentContextProbe(), onConfigurationChanged: {})

        #expect(firstModel.selected.id == provider.id)
        #expect(firstModel.selectedModel == "saved-first")
        #expect(firstModel.reasoningEffort == .high)
        #expect(secondModel.selected.id == otherProvider.id)
        firstModel.selectModel("updated-first")
        firstModel.selectReasoningEffort(.low)
        firstModel.setTool("readPage", enabled: false)

        #expect(first.model(for: provider) == "updated-first")
        #expect(first.reasoningEffort(for: provider) == .low)
        #expect(second.model(for: provider) == provider.defaultModel)
        #expect(second.enabledAgentTools(for: provider) == nil)
        #expect(secondModel.selected.id == otherProvider.id)
        let reopened = IntelligenceViewModel(settings: LLMSettings(defaults: firstDefaults),
            credentials: TestCredentialStore(), contextProbe: SilentContextProbe(), onConfigurationChanged: {})
        #expect(reopened.selectedModel == "updated-first")
        #expect(reopened.reasoningEffort == .low)
    }

    @Test func anOpenAIAddressOpensItsPage() throws {
        let name = TestDefaults.name("settings-address")
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = IntelligenceViewModel(settings: LLMSettings(defaults: defaults), credentials: TestCredentialStore(),
            contextProbe: SilentContextProbe(), onConfigurationChanged: {})
        let openAI = ProviderCatalog.openAI.id

        model.follow([openAI, "developer", "api-json"])

        #expect(model.destination == .openAI(.developer))
        #expect(model.path == [openAI, "developer"])
        #expect(model.matches([openAI, "developer", "api-json"]))

        model.follow([openAI])
        #expect(model.destination == .provider(openAI))

        model.follow(["allowed-websites"])
        #expect(model.destination == .grants)

        model.follow(["no-such-provider"])
        #expect(model.destination == .overview)
    }

    @Test func externalConnectionsLiveInAssistantSettings() throws {
        let name = TestDefaults.name("settings-connections")
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = IntelligenceViewModel(settings: LLMSettings(defaults: defaults), credentials: TestCredentialStore(),
            contextProbe: SilentContextProbe(), onConfigurationChanged: {})

        model.follow(["connections"])
        #expect(model.destination == .connections)
        #expect(model.path == ["connections"])

        let entry = try #require(SettingsIndex.all.first { $0.id == "assistant.connections" })
        #expect(entry.category == .provider)
        #expect(!SettingsIndex.all.contains { $0.id == "advanced.mcp" })
    }

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

    private func makeModel(onVoiceChange: (() -> Void)? = nil, onChange: @escaping () -> Void) -> (IntelligenceViewModel, TestProviderCatalog) {
        let catalog = TestProviderCatalog(providers: [Self.inUse, Self.other], selectedID: Self.inUse.id)
        let credentials = TestCredentialStore()
        let model = IntelligenceViewModel(
            catalog: catalog,
            credentials: credentials,
            modelProviders: ModelProviderRegistry(credentials: credentials),
            contextProbe: SilentContextProbe(),
            onVoiceConfigurationChanged: onVoiceChange,
            onConfigurationChanged: onChange
        )
        return (model, catalog)
    }

    @Test func voiceEditsDoNotRestartTheBrowserAgent() {
        let key = "openai.options." + Self.inUse.id
        let previous = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }
        OpenAISettingsStore.save(.init(), providerID: Self.inUse.id)
        var agentChanges = 0
        var voiceChanges = 0
        let (model, _) = makeModel(onVoiceChange: { voiceChanges += 1 }, onChange: { agentChanges += 1 })
        var settings = OpenAIResponseSettings()
        settings.voice.voice = "marin"
        model.saveOpenAISettings(settings)
        #expect(voiceChanges == 1)
        #expect(agentChanges == 0)
        settings.verbosity = "high"
        model.saveOpenAISettings(settings)
        #expect(agentChanges == 1)
        model.saveOpenAISettings(settings)
        #expect(agentChanges == 1)
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
            #expect(model.enabledTools == AgentToolCatalog.defaultIDs)

            model.open(Self.other)

            #expect(model.subject.id == Self.other.id)
            #expect(model.enabledTools == AgentToolCatalog.defaultIDs)
        }
    }

    @Test func editingAnotherProviderLeavesTheOneInUseAlone() {
        withCleanDefaults { model, _ in
            model.open(Self.other)
            model.setTool("playVideo", enabled: true)

            #expect(LLMSettings.enabledAgentTools(for: Self.other)?.contains("playVideo") == true)
            #expect(LLMSettings.enabledAgentTools(for: Self.inUse) == nil)

            model.showOverview()
            #expect(model.enabledTools == AgentToolCatalog.defaultIDs)
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
            model.setTool("playVideo", enabled: false)
            model.setTool("closeVideo", enabled: false)
            #expect(!model.isUsingRecommendedTools)

            model.resetToolsToRecommended()

            #expect(model.isUsingRecommendedTools)
            #expect(model.enabledTools == AgentToolCatalog.defaultIDs)
            #expect(LLMSettings.enabledAgentTools(for: Self.other) == nil)
        }
    }

    @Test func everyProviderRecommendsEveryToolBecauseToolsLoadOnDemand() {
        withCleanDefaults { model, _ in
            #expect(model.recommendedToolIDs == AgentToolCatalog.defaultIDs)
            model.open(Self.other)
            #expect(model.recommendedToolIDs == AgentToolCatalog.defaultIDs)
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
    func effectiveWindow(for provider: Provider, model: String, apiKey: String?) async -> Int? {
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
