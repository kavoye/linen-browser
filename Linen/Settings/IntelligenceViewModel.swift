// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

@MainActor
@Observable
final class IntelligenceViewModel {
    enum Destination: Hashable {
        case overview
        case provider(String)
        case picker
        case editor
        case tools
    }

    private let catalog: any ProviderCatalogProtocol
    private let credentials: any ProviderCredentialStore
    private let modelProviders: any ModelProviderResolving
    private let contextProbe: any ContextWindowProbing
    private let onConfigurationChanged: () -> Void

    private(set) var destination = Destination.overview

    private(set) var selectedID: String
    private(set) var inspectedID: String?

    var selectedModel = ""
    var reasoningEffort = LLMSettings.reasoningEffort

    var keyDraft = ""
    private(set) var keySource = CredentialStore.Source.none
    private(set) var maskedKey: String?
    private(set) var keyError: String?

    var customModelDraft = ""
    private(set) var isEditingCustomModel = false

    private(set) var availableModels: [String] = []
    private(set) var isLoadingCatalog = false
    private(set) var catalogError: String?

    private var probes: [String: ProviderReadiness] = [:]

    private(set) var customDraft: Provider?
    var customName = ""
    var customBaseURL = ""
    private(set) var customError: String?

    init(
        catalog: any ProviderCatalogProtocol = ProviderCatalog.shared,
        credentials: any ProviderCredentialStore = KeychainProviderCredentialStore(),
        modelProviders: (any ModelProviderResolving)? = nil,
        contextProbe: any ContextWindowProbing = OllamaContextProbe(),
        onConfigurationChanged: @escaping () -> Void
    ) {
        self.catalog = catalog
        self.credentials = credentials
        self.modelProviders = modelProviders ?? ModelProviderRegistry(credentials: credentials)
        self.contextProbe = contextProbe
        self.onConfigurationChanged = onConfigurationChanged
        selectedID = catalog.selected.id
        adoptSubject()
    }

    // MARK: - Providers

    var providers: [Provider] {
        catalog.all
    }

    var selected: Provider {
        catalog.provider(id: selectedID) ?? catalog.selected
    }

    var subject: Provider {
        inspectedProvider ?? selected
    }

    var inspectedProvider: Provider? {
        inspectedID.flatMap { catalog.provider(id: $0) }
    }

    var isSubjectInUse: Bool {
        subject.id == selectedID
    }

    var supportsReasoningEffort: Bool {
        modelProviders.resolve(selected).capabilities.contains(.reasoning)
    }

    var availableEfforts: [LLMSettings.ReasoningEffort] {
        let offered = ReasoningCatalog.efforts(for: selected, model: selectedModel)
        return offered.isEmpty ? ReasoningCatalog.standard : offered
    }

    var resolvedEffort: LLMSettings.ReasoningEffort {
        ReasoningCatalog.resolve(reasoningEffort, for: selected, model: selectedModel)
    }

    func onAppear() async {
        adoptSubject()
        probeLocalProviders()
        await loadCatalog()
    }

    // MARK: - Connected

    func isConnected(_ provider: Provider) -> Bool {
        if provider.isOnDevice {
            return true
        }
        if provider.needsKey {
            return credentials.source(for: provider) != .none
        }
        if provider.isCustom {
            return provider.baseURL != nil
        }
        return readiness(for: provider).level == .ready
    }

    var connected: [Provider] {
        providers.filter(isConnected).sorted { lhs, rhs in
            if (lhs.id == selectedID) != (rhs.id == selectedID) {
                return lhs.id == selectedID
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var unconnectedKeyed: [Provider] {
        providers.filter { !isConnected($0) && $0.needsKey }
    }

    var unconnectedLocal: [Provider] {
        providers.filter { !isConnected($0) && !$0.needsKey && !$0.isOnDevice }
    }

    func summary(for provider: Provider) -> String {
        var parts: [String] = []

        if provider.isOnDevice {
            parts.append(provider.blurb)
        } else {
            if provider.needsKey {
                switch credentials.source(for: provider) {
                case .keychain:
                    parts.append(String(localized: "Key saved"))
                case .environment(let name):
                    parts.append(String(localized: "Key from \(name)"))
                case .none:
                    parts.append(String(localized: "No key yet"))
                }
            } else {
                parts.append(provider.endpointLabel)
            }

            let model = LLMSettings.model(for: provider)
            if !model.isEmpty {
                parts.append(model)
            }
        }

        if case .notRunning = readiness(for: provider) {
            parts.append(String(localized: "Not responding"))
        }

        return parts.joined(separator: " · ")
    }

    // MARK: - Navigation

    func showOverview() {
        inspectedID = nil
        customDraft = nil
        customError = nil
        destination = .overview
        adoptSubject()
        Task { await loadCatalog() }
    }

    func open(_ provider: Provider) {
        customDraft = nil
        customError = nil
        inspectedID = provider.id
        destination = .provider(provider.id)
        adoptSubject()
        Task {
            if provider.isLocal, !provider.isOnDevice {
                await probe(provider)
                await discoverContextWindow(for: provider)
            }
            await loadCatalog()
        }
    }

    func showPicker() {
        customDraft = nil
        customError = nil
        destination = .picker
    }

    func showTools() {
        customDraft = nil
        customError = nil
        refreshTools()
        destination = .tools
    }

    func leaveTools() {
        if let inspectedID, catalog.provider(id: inspectedID) != nil {
            destination = .provider(inspectedID)
        } else {
            showOverview()
        }
    }

    // MARK: - Tools

    private(set) var enabledTools: Set<String> = []

    var recommendedToolIDs: Set<String> {
        AgentToolCatalog.defaultIDs(for: ContextBudget.toolTier(forWindow: subjectWindowTokens))
    }

    var isUsingRecommendedTools: Bool {
        LLMSettings.enabledAgentTools(for: subject) == nil
            || enabledTools == recommendedToolIDs
    }

    var toolWarning: String? {
        let recommended = recommendedToolIDs
        guard recommended.count < AgentToolCatalog.all.count,
              enabledTools.count > recommended.count
        else { return nil }
        return String(localized: """
            \(subject.name)’s context is small, and every tool takes a share of it. More than \
            \(recommended.count) tools can push out page content and confuse smaller models.
            """)
    }

    func isToolEnabled(_ id: String) -> Bool {
        enabledTools.contains(id)
    }

    func setTool(_ id: String, enabled: Bool) {
        if enabled {
            enabledTools.insert(id)
        } else {
            enabledTools.remove(id)
        }
        LLMSettings.setEnabledAgentTools(enabledTools, for: subject)
        if isSubjectInUse {
            onConfigurationChanged()
        }
    }

    func resetToolsToRecommended() {
        LLMSettings.setEnabledAgentTools(nil, for: subject)
        refreshTools()
        if isSubjectInUse {
            onConfigurationChanged()
        }
    }

    func refreshTools() {
        enabledTools = AgentToolCatalog.resolvedIDs(
            for: subject,
            tier: ContextBudget.toolTier(forWindow: subjectWindowTokens)
        )
    }

    func enabledToolCount(for provider: Provider) -> Int {
        AgentToolCatalog.resolvedIDs(
            for: provider,
            tier: ContextBudget.toolTier(
                forWindow: ContextWindow.tokens(
                    for: provider,
                    model: LLMSettings.model(for: provider)
                )
            )
        ).count
    }

    private var subjectWindowTokens: Int {
        ContextWindow.tokens(for: subject, model: LLMSettings.model(for: subject))
    }

    // MARK: - Context window

    private(set) var discoveredWindows: [String: Int] = [:]

    func detectedContextWindow(for provider: Provider) -> Int? {
        discoveredWindows[provider.id]
            ?? LLMSettings.discoveredContextWindow(for: provider, model: LLMSettings.model(for: provider))
    }

    func discoverContextWindow(for provider: Provider) async {
        let modelID = LLMSettings.model(for: provider)
        guard let window = await contextProbe.effectiveWindow(for: provider, model: modelID) else { return }
        discoveredWindows[provider.id] = window
        guard LLMSettings.discoveredContextWindow(for: provider, model: modelID) != window else { return }
        LLMSettings.setDiscoveredContextWindow(window, for: provider, model: modelID)
        if provider.id == selectedID {
            onConfigurationChanged()
        }
    }

    func use(_ provider: Provider) {
        guard provider.id != selectedID else { return }
        selectedID = provider.id
        catalog.select(provider)
        inspectedID = nil
        destination = .overview
        adoptSubject()
        onConfigurationChanged()
        Task {
            if provider.isLocal {
                await probe(provider)
                await discoverContextWindow(for: provider)
            }
            await loadCatalog()
        }
    }

    private func adoptSubject() {
        let provider = subject
        selectedModel = LLMSettings.model(for: provider)
        customModelDraft = selectedModel
        isEditingCustomModel = false
        keyDraft = ""
        keyError = nil
        keySource = credentials.source(for: provider)
        maskedKey = credentials.masked(for: provider)
        refreshProviderAvailability()
        availableModels = []
        catalogError = nil
        refreshTools()
    }

    var modelCatalogNotice: String? {
        guard let catalogError else { return nil }
        guard case .ready = readiness(for: subject) else { return nil }
        return catalogError
    }

    func readiness(for provider: Provider) -> ProviderReadiness {
        let availability = providerAvailability[provider.id]
            ?? modelProviders.resolve(provider).availability

        switch availability {
        case .needsCredentials:
            return .needsKey
        case .unavailable(let reason):
            return .unsupported(reason)
        case .available:
            if provider.isLocal, !provider.isOnDevice {
                return probes[provider.id] ?? .checking
            }
            return .ready(provider.endpointLabel)
        }
    }

    // MARK: - Model

    func selectModel(_ modelID: String) {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        customModelDraft = trimmed
        isEditingCustomModel = false
        selectedModel = trimmed
        LLMSettings.setModel(trimmed, for: subject)
        if isSubjectInUse {
            onConfigurationChanged()
        }
    }

    func beginCustomModelEntry() {
        customModelDraft = selectedModel
        isEditingCustomModel = true
    }

    func applyCustomModel() {
        selectModel(customModelDraft)
    }

    func selectReasoningEffort(_ effort: LLMSettings.ReasoningEffort) {
        guard effort != reasoningEffort else { return }
        reasoningEffort = effort
        LLMSettings.reasoningEffort = effort
        onConfigurationChanged()
    }

    func loadCatalog(force: Bool = false) async {
        let provider = subject
        let modelProvider = modelProviders.resolve(provider)
        guard !provider.isOnDevice,
              provider.baseURL != nil,
              case .available = modelProvider.availability,
              force || availableModels.isEmpty,
              !isLoadingCatalog
        else { return }

        isLoadingCatalog = true
        catalogError = nil
        do {
            let models = try await modelProvider.availableModels()
            guard provider.id == subject.id else { return }
            availableModels = models
            if provider.isLocal {
                probes[provider.id] = .ready(String(localized: "\(models.count) models"))
            }
            if selectedModel.isEmpty || (provider.isLocal && !models.contains(selectedModel)) {
                if let first = models.first {
                    selectModel(first)
                }
            }
        } catch {
            guard provider.id == subject.id else { return }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            catalogError = message
            if provider.isLocal {
                probes[provider.id] = .notRunning(message)
            }
        }
        isLoadingCatalog = false
    }

    // MARK: - Keys

    func saveKey() {
        let trimmed = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let failure = credentials.save(trimmed, for: subject) {
            keyError = failure
            return
        }
        keyError = nil
        keyDraft = ""
        refreshKeyState()
        availableModels = []
        onConfigurationChanged()
        Task { await loadCatalog(force: true) }
    }

    func removeKey() {
        let provider = subject
        credentials.delete(for: provider)
        keyDraft = ""
        keyError = nil
        refreshKeyState()
        availableModels = []
        catalogError = nil
        onConfigurationChanged()
    }

    private func refreshKeyState() {
        keySource = credentials.source(for: subject)
        maskedKey = credentials.masked(for: subject)
        refreshProviderAvailability()
    }

    private var providerAvailability: [String: ModelProviderAvailability] = [:]

    private func refreshProviderAvailability() {
        providerAvailability = catalog.all.reduce(into: [:]) { availability, provider in
            availability[provider.id] = modelProviders.resolve(provider).availability
        }
    }

    // MARK: - Local probes

    private func probeLocalProviders() {
        for provider in providers where provider.isLocal && !provider.isOnDevice {
            probes[provider.id] = .checking
            Task { await probe(provider) }
        }
    }

    private func probe(_ provider: Provider) async {
        guard provider.isLocal, !provider.isOnDevice else { return }
        probes[provider.id] = .checking
        do {
            let models = try await modelProviders.resolve(provider).availableModels()
            if models.isEmpty {
                probes[provider.id] = .notRunning(
                    String(localized: "Running, but no models are loaded yet.")
                )
            } else {
                probes[provider.id] = .ready(String(localized: "\(models.count) models"))
            }
        } catch {
            probes[provider.id] = .notRunning(
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    // MARK: - Custom providers

    var canCommitCustomProvider: Bool {
        !customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Self.normalizedURL(customBaseURL) != nil
    }

    func beginCustomProvider() {
        customDraft = ProviderCatalog.newCustom()
        customName = ""
        customBaseURL = ""
        customError = nil
        destination = .editor
    }

    func editCustomProvider(_ provider: Provider) {
        customDraft = provider
        customName = provider.name
        customBaseURL = provider.baseURL?.absoluteString ?? ""
        customError = nil
        destination = .editor
    }

    func cancelCustomProvider() {
        let draft = customDraft
        customDraft = nil
        customError = nil
        if let draft, providers.contains(where: { $0.id == draft.id }) {
            open(draft)
        } else {
            showOverview()
        }
    }

    func commitCustomProvider() {
        guard var draft = customDraft else { return }
        let name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            customError = String(localized: "Enter a name.")
            return
        }
        guard let url = Self.normalizedURL(customBaseURL) else {
            customError = String(localized: "This isn’t a valid URL. Try http://localhost:8000/v1")
            return
        }
        guard !Self.isInsecureRemoteEndpoint(url) else {
            customError = String(localized: "Use https — plain http would send your API key in the clear. Only localhost can use http.")
            return
        }
        draft.name = name
        draft.baseURL = url
        draft.isLocal = Self.isLocalNetwork(url)
        draft.auth = draft.isLocal ? .none : .bearer
        let host = url.host() ?? ""
        draft.blurb = String(localized: "OpenAI-compatible endpoint at \(host)")
        catalog.save(draft)
        customDraft = nil
        customError = nil
        open(draft)
        if selectedID == draft.id {
            onConfigurationChanged()
        }
    }

    func removeCustomProvider(_ provider: Provider) {
        catalog.remove(provider)
        if customDraft?.id == provider.id {
            customDraft = nil
        }
        selectedID = catalog.selected.id
        showOverview()
        onConfigurationChanged()
    }

    private static func normalizedURL(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") {
            text = "http://" + text
        }
        while text.hasSuffix("/") {
            text.removeLast()
        }
        if text.hasSuffix("/chat/completions") {
            text.removeLast("/chat/completions".count)
        }
        guard let url = URL(string: text), url.host() != nil else { return nil }
        return url
    }

    nonisolated static func isLocalNetwork(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        return isLoopback(url) || host.hasSuffix(".local")
    }

    nonisolated static func isLoopback(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    nonisolated static func isInsecureRemoteEndpoint(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "http" && !isLoopback(url)
    }
}
