// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation

nonisolated struct ModelProviderCapabilities: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let toolCalling = Self(rawValue: 1 << 0)
    static let reasoning = Self(rawValue: 1 << 1)
}

nonisolated enum ModelProviderAvailability: Equatable, Sendable {
    case available
    case needsCredentials
    case unavailable(String)
}

@MainActor
protocol ModelProvider {
    var configuration: Provider { get }
    var capabilities: ModelProviderCapabilities { get }
    var availability: ModelProviderAvailability { get }

    func availableModels() async throws -> [String]

    func makeAgent(
        model: String,
        reasoningEffort: LLMSettings.ReasoningEffort,
        toolkit: AgentToolkit,
        log: ConversationLog
    ) -> any AgentRunner

    func makeUtilityModel(model: String) -> (any LanguageModel)?
}

extension ModelProvider {
    func makeUtilityModel(model: String) -> (any LanguageModel)? {
        nil
    }
}

@MainActor
protocol ModelProviderResolving {
    func resolve(_ configuration: Provider) -> any ModelProvider
}

nonisolated protocol ProviderCredentialStore: Sendable {
    func key(for provider: Provider) -> String?
    func isConfigured(_ provider: Provider) -> Bool
    func source(for provider: Provider) -> CredentialStore.Source
    func masked(for provider: Provider) -> String?
    func save(_ key: String, for provider: Provider) -> String?
    func delete(for provider: Provider)
}

nonisolated struct KeychainProviderCredentialStore: ProviderCredentialStore {
    func key(for provider: Provider) -> String? {
        CredentialStore.key(for: provider)
    }
    func isConfigured(_ provider: Provider) -> Bool {
        CredentialStore.isConfigured(provider)
    }
    func source(for provider: Provider) -> CredentialStore.Source {
        CredentialStore.source(for: provider)
    }
    func masked(for provider: Provider) -> String? {
        CredentialStore.masked(for: provider)
    }
    func save(_ key: String, for provider: Provider) -> String? {
        CredentialStore.save(key, for: provider)
    }
    func delete(for provider: Provider) {
        CredentialStore.delete(for: provider)
    }
}

nonisolated protocol ModelCatalogFetching: Sendable {
    func fetchModels(for provider: Provider, apiKey: String?) async throws -> [String]
}

nonisolated struct HTTPModelCatalog: ModelCatalogFetching {
    func fetchModels(for provider: Provider, apiKey: String?) async throws -> [String] {
        try await ModelCatalog.fetch(for: provider, apiKey: apiKey)
    }
}

@MainActor
private struct AnyLanguageModelProvider: ModelProvider {
    let configuration: Provider
    let credentials: any ProviderCredentialStore
    let modelCatalog: any ModelCatalogFetching

    var capabilities: ModelProviderCapabilities {
        var result: ModelProviderCapabilities = [.toolCalling]
        if configuration.supportsReasoningEffort
            || configuration.adapter == .openAIResponses
            || configuration.adapter == .anthropic
            || configuration.adapter == .gemini {
            result.insert(.reasoning)
        }
        return result
    }

    var availability: ModelProviderAvailability {
        if configuration.isOnDevice {
            return AnyLanguageModelAgent.isSystemModelAvailable
                ? .available
                : .unavailable(String(localized: "Apple Intelligence isn’t available on this Mac"))
        }
        guard configuration.baseURL != nil else {
            return .unavailable(String(localized: "This provider has no endpoint set."))
        }
        if configuration.needsKey && !credentials.isConfigured(configuration) {
            return .needsCredentials
        }
        return .available
    }

    func availableModels() async throws -> [String] {
        if configuration.isOnDevice {
            return [configuration.defaultModel]
        }
        return try await modelCatalog.fetchModels(
            for: configuration,
            apiKey: credentials.key(for: configuration)
        )
    }

    func makeAgent(
        model: String,
        reasoningEffort: LLMSettings.ReasoningEffort,
        toolkit: AgentToolkit,
        log: ConversationLog
    ) -> any AgentRunner {
        let reasoningEffort = ReasoningCatalog.resolve(reasoningEffort, for: configuration, model: model)
        let window = ContextWindow.tokens(for: configuration, model: model)
        let toolIDs = AgentToolCatalog.resolvedIDs(
            for: configuration,
            tier: ContextBudget.toolTier(forWindow: window)
        )
        let budget = ContextBudget.resolve(
            windowTokens: window,
            desiredResponseTokens: LanguageModelRuntimeFactory.desiredResponseTokens(
                for: reasoningEffort,
                adapter: configuration.adapter
            ),
            toolCount: toolIDs.count
        )
        let runtime = LanguageModelRuntimeFactory.make(
            configuration: configuration,
            modelID: model,
            apiKey: credentials.key(for: configuration) ?? "",
            reasoningEffort: reasoningEffort,
            responseTokens: budget.responseTokens,
            maxToolCalls: budget.maxToolCalls
        )
        return AnyLanguageModelAgent(
            name: "\(configuration.name) (\(model))",
            model: runtime.model,
            options: runtime.options,
            answerOptions: runtime.answerOptions,
            budget: budget,
            enabledToolIDs: toolIDs,
            toolkit: toolkit,
            log: log
        )
    }

    func makeUtilityModel(model: String) -> (any LanguageModel)? {
        guard availability == .available else { return nil }
        let budget = ContextBudget.resolve(
            windowTokens: ContextWindow.tokens(for: configuration, model: model),
            desiredResponseTokens: LanguageModelRuntimeFactory.desiredResponseTokens(
                for: .low,
                adapter: configuration.adapter
            )
        )
        return LanguageModelRuntimeFactory.make(
            configuration: configuration,
            modelID: model,
            apiKey: credentials.key(for: configuration) ?? "",
            reasoningEffort: .low,
            responseTokens: budget.responseTokens,
            maxToolCalls: 1
        ).model
    }
}

@MainActor
private struct LanguageModelRuntime {
    let model: any LanguageModel
    let options: GenerationOptions
    let answerOptions: GenerationOptions

    init(
        model: any LanguageModel,
        options: GenerationOptions,
        answerOptions: GenerationOptions? = nil
    ) {
        self.model = model
        self.options = options
        self.answerOptions = answerOptions ?? options
    }
}

@MainActor
private enum LanguageModelRuntimeFactory {
    static func make(
        configuration: Provider,
        modelID: String,
        apiKey: String,
        reasoningEffort: LLMSettings.ReasoningEffort,
        responseTokens: Int,
        maxToolCalls: Int
    ) -> LanguageModelRuntime {
        var options = GenerationOptions(maximumResponseTokens: responseTokens)

        switch configuration.adapter {
        case .system:
            return LanguageModelRuntime(
                model: SystemLanguageModel.default,
                options: options
            )

        case .openAIResponses:
            let effort = openAIEffort(reasoningEffort)
            options[custom: OpenAILanguageModel.self] = .init(
                reasoning: .init(effort: effort),
                maxToolCalls: maxToolCalls
            )
            return LanguageModelRuntime(
                model: OpenAILanguageModel(
                    baseURL: configuration.baseURL ?? OpenAILanguageModel.defaultBaseURL,
                    apiKey: apiKey,
                    model: modelID,
                    apiVariant: .responses
                ),
                options: options
            )

        case .openAICompatible:
            if configuration.supportsReasoningEffort {
                options[custom: OpenAILanguageModel.self] = .init(
                    reasoningEffort: openAIEffort(reasoningEffort)
                )
            }
            return LanguageModelRuntime(
                model: OpenAILanguageModel(
                    baseURL: configuration.baseURL ?? OpenAILanguageModel.defaultBaseURL,
                    apiKey: apiKey,
                    model: modelID,
                    apiVariant: .chatCompletions
                ),
                options: options,
                answerOptions: thinkingDisabled(options, for: configuration)
            )

        case .anthropic:
            let budget = anthropicBudget(reasoningEffort)
            options[custom: AnthropicLanguageModel.self] = .init(
                thinking: budget.map { .init(budgetTokens: $0) }
            )
            let baseURL = removingPathSuffix(
                "/v1",
                from: configuration.baseURL ?? AnthropicLanguageModel.defaultBaseURL
            )
            return LanguageModelRuntime(
                model: AnthropicLanguageModel(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    model: modelID
                ),
                options: options
            )

        case .gemini:
            options[custom: GeminiLanguageModel.self] = .init(
                thinking: geminiThinking(reasoningEffort, modelID: modelID)
            )
            let configured = configuration.baseURL ?? GeminiLanguageModel.defaultBaseURL
            let baseURL = removingPathSuffix("/v1beta/openai", from: configured)
            return LanguageModelRuntime(
                model: GeminiLanguageModel(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    model: modelID
                ),
                options: options
            )
        }
    }

    private static func thinkingDisabled(
        _ options: GenerationOptions,
        for configuration: Provider
    ) -> GenerationOptions? {
        guard configuration.id == "ollama" else { return nil }
        var options = options
        options[custom: OpenAILanguageModel.self] = .init(
            reasoningEffort: openAIEffort(.none)
        )
        return options
    }

    private static func openAIEffort(
        _ effort: LLMSettings.ReasoningEffort
    ) -> OpenAILanguageModel.CustomGenerationOptions.ReasoningEffort {
        switch effort {
        case .none:
            .none
        case .minimal:
            .minimal
        case .low:
            .low
        case .medium:
            .medium
        case .high:
            .high
        }
    }

    private static func anthropicBudget(_ effort: LLMSettings.ReasoningEffort) -> Int? {
        switch effort {
        case .none:
            nil
        case .minimal:
            512
        case .low:
            1_024
        case .medium:
            4_096
        case .high:
            8_192
        }
    }

    private static func geminiThinking(
        _ effort: LLMSettings.ReasoningEffort,
        modelID: String
    ) -> GeminiLanguageModel.CustomGenerationOptions.Thinking {
        switch effort {
        case .none:
            modelID.lowercased().contains("pro") ? .budget(128) : .disabled
        case .minimal:
            .budget(512)
        case .low:
            .budget(1_024)
        case .medium:
            .budget(4_096)
        case .high:
            .budget(8_192)
        }
    }

    static func desiredResponseTokens(
        for effort: LLMSettings.ReasoningEffort,
        adapter: Provider.Adapter
    ) -> Int {
        if adapter == .anthropic {
            return (anthropicBudget(effort) ?? 0) + 700
        }
        return switch effort {
        case .none:
            700
        case .minimal:
            1_200
        case .low:
            2_000
        case .medium:
            6_000
        case .high:
            10_000
        }
    }

    private static func removingPathSuffix(_ suffix: String, from url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.path.hasSuffix(suffix)
        else { return url }
        components.path.removeLast(suffix.count)
        return components.url ?? url
    }
}

@MainActor
final class ModelProviderRegistry: ModelProviderResolving {
    typealias Factory = @MainActor (Provider) -> any ModelProvider

    private let credentials: any ProviderCredentialStore
    private let modelCatalog: any ModelCatalogFetching
    private var factories: [String: Factory]

    init(
        credentials: any ProviderCredentialStore = KeychainProviderCredentialStore(),
        modelCatalog: any ModelCatalogFetching = HTTPModelCatalog(),
        factories: [String: Factory] = [:]
    ) {
        self.credentials = credentials
        self.modelCatalog = modelCatalog
        self.factories = factories
    }

    func register(providerID: String, factory: @escaping Factory) {
        factories[providerID] = factory
    }

    func resolve(_ configuration: Provider) -> any ModelProvider {
        if let factory = factories[configuration.id] {
            return factory(configuration)
        }
        return AnyLanguageModelProvider(
            configuration: configuration,
            credentials: credentials,
            modelCatalog: modelCatalog
        )
    }
}

@MainActor
protocol ProviderCatalogProtocol: AnyObject {
    var all: [Provider] { get }
    var selected: Provider { get }

    func provider(id: String) -> Provider?
    func select(_ provider: Provider)
    func save(_ provider: Provider)
    func remove(_ provider: Provider)
}

extension ProviderCatalog: ProviderCatalogProtocol {}
