// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Shared model helpers inherit the initiating window's settings through task-local scope.
nonisolated extension LLMSettings {
    static var providerID: String {
        get { current.providerID }
        set { current.providerID = newValue }
    }

    static var reasoningEffort: ReasoningEffort {
        get { current.reasoningEffort }
        set { current.reasoningEffort = newValue }
    }

    static func model(for provider: Provider) -> String {
        current.model(for: provider)
    }

    static func setModel(_ model: String, for provider: Provider) {
        current.setModel(model, for: provider)
    }

    static func reasoningEffort(for provider: Provider) -> ReasoningEffort {
        current.reasoningEffort(for: provider)
    }

    static func setReasoningEffort(_ effort: ReasoningEffort, for provider: Provider) {
        current.setReasoningEffort(effort, for: provider)
    }

    static func contextWindow(for provider: Provider) -> Int? {
        current.contextWindow(for: provider)
    }

    static func setContextWindow(_ tokens: Int?, for provider: Provider) {
        current.setContextWindow(tokens, for: provider)
    }

    static func discoveredContextWindow(for provider: Provider, model: String) -> Int? {
        current.discoveredContextWindow(for: provider, model: model)
    }

    static func setDiscoveredContextWindow(_ tokens: Int?, for provider: Provider, model: String) {
        current.setDiscoveredContextWindow(tokens, for: provider, model: model)
    }

    static func enabledAgentTools(for provider: Provider) -> Set<String>? {
        current.enabledAgentTools(for: provider)
    }

    static func setEnabledAgentTools(_ ids: Set<String>?, for provider: Provider) {
        current.setEnabledAgentTools(ids, for: provider)
    }
}

/// Provider definitions are app-wide; the selected provider belongs to a profile.
@MainActor
final class ProfileProviderCatalog: ProviderCatalogProtocol {
    private let settings: LLMSettings

    init(settings: LLMSettings) {
        self.settings = settings
    }

    var all: [Provider] {
        ProviderCatalog.shared.all
    }
    var selected: Provider {
        provider(id: settings.providerID) ?? ProviderCatalog.openAI
    }

    func provider(id: String) -> Provider? {
        ProviderCatalog.shared.provider(id: id)
    }

    func select(_ provider: Provider) {
        settings.providerID = provider.id
    }

    func save(_ provider: Provider) {
        ProviderCatalog.shared.save(provider)
    }

    func remove(_ provider: Provider) {
        LLMSettings.$scoped.withValue(settings) {
            ProviderCatalog.shared.remove(provider)
        }
    }
}
