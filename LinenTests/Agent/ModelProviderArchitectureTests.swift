// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

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

@MainActor
private struct TestModelProvider: ModelProvider {
    let configuration: Provider
    let capabilities: ModelProviderCapabilities
    let availability: ModelProviderAvailability
    let models: [String]

    func availableModels() async throws -> [String] {
        models
    }

    func makeAgent(
        model: String,
        reasoningEffort: LLMSettings.ReasoningEffort,
        toolkit: AgentToolkit,
        log: ConversationLog
    ) -> any AgentRunner {
        TestAgentRunner()
    }
}

@MainActor
private final class TestAgentRunner: AgentRunner {
    let name = "Mock model"

    func prepare() {}
    func discardSession(forTab tabID: UUID) {}
    func transferSession(from tabID: UUID, to newTabID: UUID) {}

    func run(
        utterance: String,
        task: AgentTaskContext,
        into reply: AgentReplyModel,
        speech: any SpeechOutput
    ) async {}
}

@MainActor
struct ModelProviderArchitectureTests {
    @Test func registeredMockProviderDrivesSettingsWithoutNetwork() async {
        let configuration = Provider(
            id: "mock",
            name: "Mock Provider",
            blurb: "Deterministic test provider",
            symbol: "checkmark",
            baseURL: URL(string: "https://models.example/v1"),
            wire: .chatCompletions,
            auth: .none,
            defaultModel:
                "mock-fast",
            supportsReasoningEffort: false
        )
        let credentials = TestCredentialStore()
        let catalog = TestProviderCatalog(providers: [configuration], selectedID: configuration.id)
        let registry = ModelProviderRegistry(
            credentials: credentials,
            factories: [
                configuration.id: { provider in
                    TestModelProvider(
                        configuration: provider,
                        capabilities: [.toolCalling, .reasoning],
                        availability: .available,
                        models: ["mock-fast", "mock-deep"]
                    )
                },
            ]
        )
        var configurationChanges = 0
        let model = IntelligenceViewModel(
            catalog: catalog,
            credentials: credentials,
            modelProviders: registry,
            onConfigurationChanged: { configurationChanges += 1 }
        )

        await model.onAppear()

        #expect(model.providers == [configuration])
        #expect(model.availableModels == ["mock-fast", "mock-deep"])
        #expect(model.supportsReasoningEffort)
        #expect(model.readiness(for: configuration) == .ready("models.example"))
        #expect(configurationChanges == 0)
    }

    @Test func builtInAdaptersExposeNativeReasoningCapabilities() {
        let registry = ModelProviderRegistry(credentials: TestCredentialStore())
        let anthropic = ProviderCatalog.builtIn.first { $0.id == "anthropic" }!
        let google = ProviderCatalog.builtIn.first { $0.id == "google" }!
        let ollama = ProviderCatalog.builtIn.first { $0.id == "ollama" }!

        #expect(anthropic.adapter == .anthropic)
        #expect(google.adapter == .gemini)
        #expect(ollama.adapter == .openAICompatible)
        #expect(registry.resolve(anthropic).capabilities.contains(.reasoning))
        #expect(registry.resolve(google).capabilities.contains(.reasoning))
        #expect(!registry.resolve(ollama).capabilities.contains(.reasoning))
    }
}

/// Why `Provider.init(from:)` is written by hand: an app update that adds a
/// field must never empty the list of endpoints the user added themselves.
/// Delete that initialiser and these fail.
@MainActor
struct ProviderPersistenceTests {
    /// JSON the way an older version would have saved it: several of
    /// today's keys missing entirely.
    @Test func aProviderSavedByAnOlderVersionStillDecodes() throws {
        let stored = Data("""
        [{"id": "my-server", "baseURL": "http://192.168.1.20:8080", "wire": "chatCompletions"}]
        """.utf8)

        let decoded = try JSONDecoder().decode([Provider].self, from: stored)
        let provider = try #require(decoded.first)

        #expect(provider.id == "my-server")
        #expect(provider.name == "my-server")
        #expect(provider.auth == .bearer)
        #expect(provider.adapter == .openAICompatible)
        #expect(provider.suggestedModels.isEmpty)
        #expect(!provider.supportsReasoningEffort)
    }

    /// Whatever the stored flag says, anything coming back through this
    /// path is a custom provider - built-ins are never persisted.
    @Test func everythingDecodedIsCustom() throws {
        let stored = Data("""
        [{"id": "sneaky", "isCustom": false}]
        """.utf8)

        let provider = try #require(try JSONDecoder().decode([Provider].self, from: stored).first)
        #expect(provider.isCustom)
    }

    @Test func aRoundTripLosesNothing() throws {
        let original = Provider(
            id: "corp-proxy",
            name: "Corp Proxy",
            blurb: "The office gateway",
            symbol: "building.2",
            baseURL: URL(string: "https://llm.corp.example"),
            wire: .chatCompletions,
            auth: .bearer,
            supportsReasoningEffort: true,
            isCustom: true
        )

        let decoded = try JSONDecoder().decode(
            Provider.self,
            from: JSONEncoder().encode(original)
        )
        #expect(decoded == original)
    }
}
