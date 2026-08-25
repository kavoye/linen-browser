// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

nonisolated struct Provider: Identifiable, Hashable, Codable, Sendable {
    enum Wire: String, Codable, Hashable {
        case appleOnDevice
        case responses
        case chatCompletions
    }

    enum Adapter: String, Codable, Hashable {
        case system
        case openAIResponses
        case openAICompatible
        case anthropic
        case gemini
    }

    enum Auth: String, Codable, Hashable {
        case bearer
        case none
    }

    struct ModelSuggestion: Identifiable, Hashable, Codable {
        let id: String
        let name: String
        let detail: String
    }

    var id: String
    var name: String
    var blurb: String
    var symbol: String
    var baseURL: URL?
    var wire: Wire
    var adapter: Adapter
    var auth: Auth
    var isLocal = false
    var environmentKey: String?
    var consoleURL: URL?
    var setupHint: String?
    var suggestedModels: [ModelSuggestion] = []
    var defaultModel = ""
    var supportsReasoningEffort = false
    var isCustom = false

    var needsKey: Bool {
        auth == .bearer
    }

    var endpointLabel: String {
        guard let baseURL else { return String(localized: "on this Mac") }
        let host = baseURL.host() ?? baseURL.absoluteString
        if let port = baseURL.port, isLocal {
            return "\(host):\(port)"
        }
        return host
    }

    func url(path: String) -> URL? {
        baseURL?.appendingPathComponent(path)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? id
        blurb = try container.decodeIfPresent(String.self, forKey: .blurb) ?? ""
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
            ?? "point.3.connected.trianglepath.dotted"
        baseURL = try container.decodeIfPresent(URL.self, forKey: .baseURL)
        wire = try container.decodeIfPresent(Wire.self, forKey: .wire) ?? .chatCompletions
        adapter = try container.decodeIfPresent(Adapter.self, forKey: .adapter)
            ?? Self.defaultAdapter(providerID: id, wire: wire)
        auth = try container.decodeIfPresent(Auth.self, forKey: .auth) ?? .bearer
        isLocal = try container.decodeIfPresent(Bool.self, forKey: .isLocal) ?? false
        environmentKey = try container.decodeIfPresent(String.self, forKey: .environmentKey)
        consoleURL = try container.decodeIfPresent(URL.self, forKey: .consoleURL)
        setupHint = try container.decodeIfPresent(String.self, forKey: .setupHint)
        suggestedModels = try container.decodeIfPresent([ModelSuggestion].self, forKey: .suggestedModels) ?? []
        defaultModel = try container.decodeIfPresent(String.self, forKey: .defaultModel) ?? ""
        supportsReasoningEffort = try container.decodeIfPresent(Bool.self, forKey: .supportsReasoningEffort) ?? false
        isCustom = true
    }

    init(
        id: String,
        name: String,
        blurb: String,
        symbol: String,
        baseURL: URL?,
        wire: Wire,
        adapter: Adapter? = nil,
        auth: Auth,
        isLocal: Bool = false,
        environmentKey: String? = nil,
        consoleURL: URL? = nil,
        setupHint: String? = nil,
        suggestedModels: [ModelSuggestion] = [],
        defaultModel:
            String = "",
        supportsReasoningEffort: Bool = false,
        isCustom: Bool = false
    ) {
        self.id = id
        self.name = name
        self.blurb = blurb
        self.symbol = symbol
        self.baseURL = baseURL
        self.wire = wire
        self.adapter = adapter ?? Self.defaultAdapter(providerID: id, wire: wire)
        self.auth = auth
        self.isLocal = isLocal
        self.environmentKey = environmentKey
        self.consoleURL = consoleURL
        self.setupHint = setupHint
        self.suggestedModels = suggestedModels
        self.defaultModel = defaultModel
        self.supportsReasoningEffort = supportsReasoningEffort
        self.isCustom = isCustom
    }

    var isOnDevice: Bool {
        adapter == .system
    }

    var adapterLabel: LocalizedStringResource {
        switch adapter {
        case .system:
            "on-device"
        case .openAIResponses:
            "responses"
        case .openAICompatible:
            "OpenAI compatible"
        case .anthropic:
            "Anthropic"
        case .gemini:
            "Gemini"
        }
    }

    private static func defaultAdapter(providerID: String, wire: Wire) -> Adapter {
        if providerID == "anthropic" {
            return .anthropic
        }
        if providerID == "google" {
            return .gemini
        }
        return switch wire {
        case .appleOnDevice:
            .system
        case .responses:
            .openAIResponses
        case .chatCompletions:
            .openAICompatible
        }
    }
}

// MARK: - Catalog

@MainActor
@Observable
final class ProviderCatalog {
    static let shared = ProviderCatalog()

    private static let customKey = "llm.customProviders"

    private(set) var custom: [Provider]
    private(set) var all: [Provider]

    private init() {
        let custom = Self.loadCustom()
        self.custom = custom
        all = Self.alphabetized(Self.builtIn + custom)
    }

    func provider(id: String) -> Provider? {
        all.first { $0.id == id }
    }

    var selected: Provider {
        provider(id: LLMSettings.providerID) ?? Self.openAI
    }

    func select(_ provider: Provider) {
        LLMSettings.providerID = provider.id
    }

    // MARK: Custom providers

    static func newCustom() -> Provider {
        Provider(
            id: "custom.\(UUID().uuidString.prefix(8).lowercased())",
            name: "",
            blurb: String(localized: "OpenAI-compatible endpoint"),
            symbol: "point.3.connected.trianglepath.dotted",
            baseURL: nil,
            wire: .chatCompletions,
            auth: .bearer,
            supportsReasoningEffort: false,
            isCustom: true
        )
    }

    func save(_ provider: Provider) {
        guard provider.isCustom else { return }
        if let index = custom.firstIndex(where: { $0.id == provider.id }) {
            custom[index] = provider
        } else {
            custom.append(provider)
        }
        refreshAll()
        persistCustom()
    }

    func remove(_ provider: Provider) {
        guard provider.isCustom else { return }
        custom.removeAll { $0.id == provider.id }
        CredentialStore.delete(for: provider)
        if LLMSettings.providerID == provider.id {
            LLMSettings.providerID = Self.openAI.id
        }
        refreshAll()
        persistCustom()
    }

    private func refreshAll() {
        all = Self.alphabetized(Self.builtIn + custom)
    }

    private static func alphabetized(_ providers: [Provider]) -> [Provider] {
        providers.sorted { lhs, rhs in
            let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
        }
    }

    private func persistCustom() {
        guard let data = try? JSONEncoder().encode(custom) else { return }
        UserDefaults.standard.set(data, forKey: Self.customKey)
    }

    private static func loadCustom() -> [Provider] {
        guard let data = UserDefaults.standard.data(forKey: customKey),
              let elements = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else { return [] }
        return elements.compactMap { element in
            guard let elementData = try? JSONSerialization.data(withJSONObject: element) else { return nil }
            return try? JSONDecoder().decode(Provider.self, from: elementData)
        }
    }
}

// MARK: - Built-in providers

extension ProviderCatalog {
    nonisolated static let openAI = Provider(
        id: "openai",
        name: "OpenAI",
        blurb: String(localized: "Streaming, tool calling, and reasoning control."),
        symbol: "sparkle",
        baseURL: URL(string: "https://api.openai.com/v1"),
        wire: .responses,
        adapter: .openAIResponses,
        auth: .bearer,
        environmentKey: "OPENAI_API_KEY",
        consoleURL: URL(string: "https://platform.openai.com/api-keys"),
        suggestedModels: [
            .init(id: "gpt-5.6-luna", name: "Luna", detail: String(localized: "fastest · default")),
            .init(id: "gpt-5.6", name: "Flagship", detail: String(localized: "most capable")),
            .init(id: "gpt-5.1", name: "5.1", detail: String(localized: "previous flagship")),
            .init(id: "gpt-5-mini", name: "Mini", detail: String(localized: "cheapest")),
        ],
        defaultModel:
            "gpt-5.6-luna",
        supportsReasoningEffort: true
    )

    nonisolated static let appleOnDevice = Provider(
        id: "apple",
        name: "Apple Intelligence",
        blurb: String(localized: "Runs on this Mac. No API key required."),
        symbol: "apple.logo",
        baseURL: nil,
        wire: .appleOnDevice,
        adapter: .system,
        auth: .none,
        isLocal: true,
        setupHint: String(localized: "Turn on Apple Intelligence in System Settings."),
        defaultModel:
            "on-device"
    )

    nonisolated static let builtIn: [Provider] = [
        openAI,
        appleOnDevice,

        Provider(
            id: "anthropic",
            name: "Anthropic",
            blurb: String(localized: "Claude, with extended thinking control."),
            symbol: "a.circle",
            baseURL: URL(string: "https://api.anthropic.com/v1"),
            wire: .chatCompletions,
            adapter: .anthropic,
            auth: .bearer,
            environmentKey: "ANTHROPIC_API_KEY",
            consoleURL: URL(string: "https://console.anthropic.com/settings/keys"),
            suggestedModels: [
                .init(id: "claude-sonnet-5", name: "Sonnet", detail: String(localized: "balanced · default")),
                .init(id: "claude-opus-5", name: "Opus", detail: String(localized: "most capable")),
                .init(id: "claude-haiku-4-5-20251001", name: "Haiku", detail: String(localized: "fastest")),
            ],
            defaultModel:
                "claude-sonnet-5", supportsReasoningEffort: true
        ),

        Provider(
            id: "ollama",
            name: "Ollama",
            blurb: String(localized: "Your own models, running locally."),
            symbol: "desktopcomputer",
            baseURL: URL(string: "http://localhost:11434/v1"),
            wire: .chatCompletions,
            auth: .none,
            isLocal: true,
            consoleURL: URL(string: "https://ollama.com/download"),
            setupHint: String(localized: "Start it with `ollama serve`, then pull a tool-capable model such as `qwen3.5` or `llama3.1`."),
            defaultModel:
                "qwen3.5"
        ),

        Provider(
            id: "lmstudio",
            name: "LM Studio",
            blurb: String(localized: "Local models with a GUI, on port 1234."),
            symbol: "macmini",
            baseURL: URL(string: "http://localhost:1234/v1"),
            wire: .chatCompletions,
            auth: .none,
            isLocal: true,
            consoleURL: URL(string: "https://lmstudio.ai"),
            setupHint: String(localized: "Load a model, then start the local server from LM Studio’s Developer tab.")
        ),

        Provider(
            id: "google",
            name: "Google",
            blurb: String(localized: "Gemini, with thinking budget control."),
            symbol: "g.circle",
            baseURL: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai"),
            wire: .chatCompletions,
            adapter: .gemini,
            auth: .bearer,
            environmentKey: "GEMINI_API_KEY",
            consoleURL: URL(string: "https://aistudio.google.com/apikey"),
            defaultModel:
                "gemini-2.5-flash",
            supportsReasoningEffort: true
        ),

        Provider(
            id: "openrouter",
            name: "OpenRouter",
            blurb: String(localized: "Hundreds of models from every vendor, with a single key."),
            symbol: "arrow.triangle.branch",
            baseURL: URL(string: "https://openrouter.ai/api/v1"),
            wire: .chatCompletions,
            auth: .bearer,
            environmentKey: "OPENROUTER_API_KEY",
            consoleURL: URL(string: "https://openrouter.ai/keys")
        ),

        Provider(
            id: "groq",
            name: "Groq",
            blurb: String(localized: "Open models served fast enough for voice."),
            symbol: "bolt",
            baseURL: URL(string: "https://api.groq.com/openai/v1"),
            wire: .chatCompletions,
            auth: .bearer,
            environmentKey: "GROQ_API_KEY",
            consoleURL: URL(string: "https://console.groq.com/keys")
        ),

        Provider(
            id: "xai",
            name: "xAI",
            blurb: "Grok.",
            symbol: "x.circle",
            baseURL: URL(string: "https://api.x.ai/v1"),
            wire: .chatCompletions,
            auth: .bearer,
            environmentKey: "XAI_API_KEY",
            consoleURL: URL(string: "https://console.x.ai"),
            defaultModel:
                "grok-4"
        ),

        Provider(
            id: "deepseek",
            name: "DeepSeek",
            blurb: String(localized: "Inexpensive models that think before answering."),
            symbol: "water.waves",
            baseURL: URL(string: "https://api.deepseek.com/v1"),
            wire: .chatCompletions,
            auth: .bearer,
            environmentKey: "DEEPSEEK_API_KEY",
            consoleURL: URL(string: "https://platform.deepseek.com/api_keys"),
            defaultModel:
                "deepseek-chat"
        ),

        Provider(
            id: "mistral",
            name: "Mistral",
            blurb: String(localized: "European models, with small and fast tiers."),
            symbol: "wind",
            baseURL: URL(string: "https://api.mistral.ai/v1"),
            wire: .chatCompletions,
            auth: .bearer,
            environmentKey: "MISTRAL_API_KEY",
            consoleURL: URL(string: "https://console.mistral.ai/api-keys"),
            defaultModel:
                "mistral-medium-latest"
        ),
    ]
}

// MARK: - Settings

nonisolated enum LLMSettings {
    private static let providerKey = "llm.provider"
    private static let reasoningKey = "llm.reasoningEffort"

    nonisolated(unsafe) static var defaults: UserDefaults = .standard

    private static func modelKey(for provider: Provider) -> String {
        "llm.model.\(provider.id)"
    }

    static var providerID: String {
        get { defaults.string(forKey: providerKey) ?? ProviderCatalog.openAI.id }
        set { defaults.set(newValue, forKey: providerKey) }
    }

    static func model(for provider: Provider) -> String {
        let stored = defaults.string(forKey: modelKey(for: provider))
        if let stored, !stored.isEmpty {
            return stored
        }
        return provider.defaultModel
    }

    static func setModel(_ model: String, for provider: Provider) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(trimmed, forKey: modelKey(for: provider))
    }

    enum ReasoningEffort: String, CaseIterable, Identifiable {
        case none
        case minimal
        case low
        case medium
        case high

        var id: String {
            rawValue
        }

        var label: LocalizedStringResource {
            switch self {
            case .none:
                "None"
            case .minimal:
                "Minimal"
            case .low:
                "Low"
            case .medium:
                "Medium"
            case .high:
                "High"
            }
        }

        var caption: LocalizedStringResource {
            switch self {
            case .none:
                "Answers straight away."
            case .minimal:
                "Thinks for a moment first."
            case .low:
                "Plans a little before acting."
            case .medium:
                "Works through multi-step tasks."
            case .high:
                "Thinks as long as it needs."
            }
        }
    }

    static var reasoningEffort: ReasoningEffort {
        get {
            ReasoningEffort(rawValue: defaults.string(forKey: reasoningKey) ?? "") ?? .low
        }
        set { defaults.set(newValue.rawValue, forKey: reasoningKey) }
    }
}
