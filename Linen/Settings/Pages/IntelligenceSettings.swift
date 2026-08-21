// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Observation
import SwiftUI

struct AssistantSettings: View {
    @Bindable var model: IntelligenceViewModel
    let coordinator: AppCoordinator

    var body: some View {
        Group {
            switch model.destination {
            case .overview:
                AssistantOverview(model: model, coordinator: coordinator)
            case .provider:
                ProviderPage(model: model, coordinator: coordinator)
            case .picker:
                AddProviderPage(model: model)
            case .editor:
                CustomProviderEditor(model: model)
            case .tools:
                AgentToolsPage(model: model)
            }
        }
        .task { await model.onAppear() }
    }
}

// MARK: - Who answers

private struct AssistantOverview: View {
    @Bindable var model: IntelligenceViewModel
    let coordinator: AppCoordinator

    var body: some View {
        SettingsPageHeader(
            title: "Assistant",
            caption: "Which provider answers, and what it may do on its own."
        )

        SettingsCard {
            AnsweringRow(model: model, coordinator: coordinator)

            if !model.selected.isOnDevice {
                RowSeparator()
                ModelControl(model: model)
            }

            RowSeparator()

            DetailRow(title: "Tools") {
                HStack(spacing: 7) {
                    Text("\(model.enabledTools.count) of \(AgentToolCatalog.all.count)")
                        .font(Theme.Font.secondary)
                        .foregroundStyle(.secondary)

                    SettingsButton(title: "Customize…") {
                        model.showTools()
                    }
                }
            }
            .settingsAnchor("assistant.tools")
        }
        .padding(.top, 6)

        if model.supportsReasoningEffort {
            ThinkingSection(model: model)
        }

        VoiceSection(coordinator: coordinator)

        SettingsSection(title: "Providers", symbol: "link") {
            ForEach(model.connected) { provider in
                ProviderRow(
                    provider: provider,
                    summary: model.summary(for: provider),
                    isInUse: provider.id == model.selectedID
                ) {
                    model.open(provider)
                }

                RowSeparator()
            }

            AddRow(title: "Add Provider…") { model.showPicker() }
        }
        .settingsAnchor("provider.connected")

        AssistantGrantsSection()

        Footnote(AIDisclosure.settingsCaption)
    }
}

private struct AnsweringRow: View {
    @Bindable var model: IntelligenceViewModel
    let coordinator: AppCoordinator

    private var active: Provider? {
        coordinator.activeProvider
    }

    var body: some View {
        if let active, active.id == model.selectedID {
            HStack(spacing: 11) {
                ProviderBrandIcon(providerID: active.id, size: 20)
                    .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: active.name)
                        .font(Theme.Font.rowTitle)

                    Text(verbatim: readyCaption(active))
                        .font(Theme.Font.secondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                if !active.isOnDevice {
                    CatalogRefreshButton(model: model)
                }
            }
            .padding(.vertical, SettingsMetrics.rowPaddingV)
        } else if let active {
            StatusRow(
                tint: Theme.warning,
                symbol: "exclamationmark",
                title: "\(model.selected.name) isn’t ready",
                caption: "Linen is using \(active.name) instead."
            ) {
                SettingsButton(title: "Set Up…", isProminent: true) {
                    model.open(model.selected)
                }
            }
        } else {
            StatusRow(
                tint: Theme.danger,
                symbol: "xmark",
                title: "No provider is ready",
                caption: "Add a provider, or fix the one you chose."
            ) {
                SettingsButton(title: "Add Provider…", isProminent: true) {
                    model.showPicker()
                }
            }
        }
    }

    private func readyCaption(_ provider: Provider) -> String {
        if provider.isOnDevice {
            return provider.blurb
        }
        return LLMSettings.model(for: provider)
    }
}

private struct VoiceSection: View {
    let coordinator: AppCoordinator

    @State private var talk = ActivationSettings.talk
    @State private var recording: String?

    var body: some View {
        SettingsSection(title: "Voice", symbol: "waveform") {
            DetailRow(
                title: "Read aloud",
                caption: "Speak answers as they arrive. Change the voice or speed in [System Settings](x-apple.systempreferences:com.apple.preference.universalaccess?TextToSpeech)."
            ) {
                SettingsToggle(Binding(
                    get: { !coordinator.isSpeechMuted },
                    set: { enabled in
                        if enabled == coordinator.isSpeechMuted {
                            coordinator.toggleSpeechMute()
                        }
                    }
                ))
            }
            .settingsAnchor("voice.readAloud")

            RowSeparator()

            DetailRow(
                title: "Push to talk",
                caption: "Hold while speaking. Release to send."
            ) {
                ShortcutRecorder(
                    id: "talk",
                    recording: $recording,
                    shortcut: talk,
                    defaultShortcut:
                        ActivationSettings.defaultTalk
                ) { recorded in
                    talk = recorded
                    ActivationSettings.talk = recorded
                    coordinator.reloadActivation()
                }
            }
            .settingsAnchor("voice.talk")
        }
        .onChange(of: recording) { _, listening in
            coordinator.setActivationSuspended(listening != nil)
        }
    }
}

private struct ThinkingSection: View {
    @Bindable var model: IntelligenceViewModel

    var body: some View {
        SettingsSection(
            title: "Thinking",
            symbol: "brain",
            footnote: "Applies to every provider that supports it."
        ) {
            OptionList(
                options: LLMSettings.ReasoningEffort.allCases.map {
                    .init(value: $0, label: $0.label, caption: $0.caption)
                },
                selection: model.reasoningEffort,
                onSelect: model.selectReasoningEffort
            )
        }
        .settingsAnchor("provider.thinking")
    }
}

// MARK: - One provider

private struct ProviderRow: View {
    let provider: Provider
    let summary: String
    let isInUse: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ProviderBrandIcon(providerID: provider.id, size: 20)
                    .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: provider.name)
                        .font(Theme.Font.rowTitle)

                    if !summary.isEmpty {
                        Text(verbatim: summary)
                            .font(Theme.Font.secondary)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 8)

                if isInUse {
                    Tag("In use")
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .help(Text(verbatim: provider.blurb))
    }
}

private struct ProviderPage: View {
    @Bindable var model: IntelligenceViewModel
    let coordinator: AppCoordinator

    @State private var confirmingEndpointRemoval = false

    private var provider: Provider {
        model.subject
    }
    private var readiness: ProviderReadiness {
        model.readiness(for: provider)
    }

    private var endpoint: String? {
        guard let url = provider.baseURL else { return nil }
        let host = url.host() ?? url.absoluteString
        let port = url.port.map { ":\($0)" } ?? ""
        return host + port + url.path()
    }

    var body: some View {
        SubPageHeader(backTitle: "Assistant") { model.showOverview() }

        HStack(alignment: .top, spacing: 12) {
            SettingsPageHeader(
                verbatimTitle: provider.name,
                detail: endpoint,
                verbatimCaption: endpoint == nil ? provider.blurb : nil
            )

            if model.isSubjectInUse {
                Tag("In use")
                    .padding(.top, 5)
            } else {
                SettingsButton(title: "Use \(provider.name)") {
                    model.use(provider)
                }
                .disabled(readiness.level != .ready)
            }
        }

        SettingsCard {
            ReadinessRow(model: model)

            if !provider.isOnDevice {
                RowSeparator()
                ModelControl(model: model)

                if let window = model.detectedContextWindow(for: provider) {
                    RowSeparator()
                    DetailRow(
                        title: "Context window",
                        caption: "Reported by \(provider.name) for the selected model."
                    ) {
                        Text("\(window.formatted()) tokens")
                            .font(Theme.Font.control)
                            .foregroundStyle(.secondary)
                    }
                }

                if provider.needsKey {
                    RowSeparator()
                    APIKeyRow(model: model)
                        .settingsAnchor("provider.key")
                }

                if provider.isCustom {
                    RowSeparator()
                    endpointRow
                }
            }

            RowSeparator()

            DetailRow(title: "Tools") {
                HStack(spacing: 7) {
                    Text("\(model.enabledToolCount(for: provider)) of \(AgentToolCatalog.all.count)")
                        .font(Theme.Font.secondary)
                        .foregroundStyle(.secondary)

                    SettingsButton(title: "Customize…") {
                        model.showTools()
                    }
                }
            }
            .settingsAnchor("provider.tools")
        }
        .padding(.top, 6)

        if let hint = provider.setupHint, readiness.level != .ready {
            Text(verbatim: hint)
                .font(Theme.Font.label)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, -20)
        }

        if !provider.isCustom, model.keySource == .keychain {
            SectionActions {
                RemoveKeyButton(model: model)
            }
        }
    }

    @ViewBuilder
    private var endpointRow: some View {
        DetailRow(title: "Endpoint") {
            HStack(spacing: 7) {
                SettingsButton(title: "Edit") { model.editCustomProvider(provider) }
                SettingsButton(title: "Remove", isDestructive: true, symbol: "trash") {
                    confirmingEndpointRemoval = true
                }
                Tag(provider.adapterLabel)
            }
        }
        .settingsAnchor("provider.endpoint")
        .confirmationDialog(
            "Remove “\(provider.name)”?",
            isPresented: $confirmingEndpointRemoval
        ) {
            Button("Remove Endpoint", role: .destructive) {
                model.removeCustomProvider(provider)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its name and URL are removed. The server itself isn’t affected.")
        }
    }
}

private struct ReadinessRow: View {
    @Bindable var model: IntelligenceViewModel

    private var provider: Provider {
        model.subject
    }

    var body: some View {
        switch model.readiness(for: provider) {
        case .ready(let detail):
            StatusRow(
                tint: Theme.success,
                symbol: "checkmark",
                title: "Ready",
                verbatimCaption: detail
            ) {
                if !provider.isOnDevice {
                    refresh
                }
            }

        case .needsKey:
            StatusRow(
                tint: Theme.warning,
                symbol: "key",
                title: "Needs a key",
                caption: "Add a key to let \(provider.name) answer."
            ) {}

        case .notRunning(let why):
            StatusRow(
                tint: Theme.warning,
                symbol: "exclamationmark",
                title: "Not responding",
                verbatimCaption: why
            ) {
                refresh
            }

        case .checking:
            StatusRow(tint: .secondary, symbol: "ellipsis", title: "Checking…") {}

        case .unsupported(let why):
            StatusRow(
                tint: Theme.danger,
                symbol: "xmark",
                title: "Unavailable",
                verbatimCaption: why
            ) {}
        }
    }

    private var refresh: some View {
        CatalogRefreshButton(model: model)
    }
}

private struct CatalogRefreshButton: View {
    @Bindable var model: IntelligenceViewModel

    var body: some View {
        IconButton(
            symbol: "arrow.clockwise",
            help: "Check this provider again",
            isBusy: model.isLoadingCatalog
        ) {
            Task { await model.loadCatalog(force: true) }
        }
        .disabled(model.isLoadingCatalog)
    }
}

private struct RemoveKeyButton: View {
    @Bindable var model: IntelligenceViewModel

    @State private var confirming = false

    var body: some View {
        SettingsButton(title: "Remove Key", isDestructive: true, symbol: "trash") {
            confirming = true
        }
        .confirmationDialog(
            "Remove the \(model.subject.name) key?",
            isPresented: $confirming
        ) {
            Button("Remove Key", role: .destructive) { model.removeKey() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The key is deleted from your Keychain, and \(model.subject.name) stops answering until you add another.")
        }
    }
}

// MARK: - Adding one

private struct AddProviderPage: View {
    @Bindable var model: IntelligenceViewModel

    var body: some View {
        SubPageHeader(backTitle: "Assistant") { model.showOverview() }

        SettingsPageHeader(
            title: "Add a provider"
        )

        if !model.unconnectedKeyed.isEmpty {
            SettingsSection(
                title: "Needs an API key",
                symbol: "key",
                footnote: "Keys are saved to your Keychain."
            ) {
                ForEach(Array(model.unconnectedKeyed.enumerated()), id: \.element.id) { index, provider in
                    if index > 0 {
                        RowSeparator()
                    }

                    ProviderRow(
                        provider: provider,
                        summary: provider.blurb,
                        isInUse: false
                    ) {
                        model.open(provider)
                    }
                }
            }
        }

        SettingsSection(title: "Needs a server you run", symbol: "desktopcomputer") {
            ForEach(Array(model.unconnectedLocal.enumerated()), id: \.element.id) { index, provider in
                if index > 0 {
                    RowSeparator()
                }

                ProviderRow(
                    provider: provider,
                    summary: model.summary(for: provider),
                    isInUse: false
                ) {
                    model.open(provider)
                }
            }

            if !model.unconnectedLocal.isEmpty {
                RowSeparator()
            }

            DetailRow(
                title: "Your own server",
                caption: "Any server that uses the OpenAI chat API."
            ) {
                SettingsButton(title: "Set Up…") { model.beginCustomProvider() }
            }
        }
    }
}

// MARK: - Rows

private struct APIKeyRow: View {
    @Bindable var model: IntelligenceViewModel

    @State private var entering = false

    private var provider: Provider {
        model.subject
    }

    private var caption: LocalizedStringResource? {
        switch model.keySource {
        case .keychain:
            if let masked = model.maskedKey {
                return "`\(masked)` is saved in your Keychain."
            }
            return "Saved in your Keychain."
        case .environment(let name):
            return "Using `\(name)` from the environment."
        case .none:
            return nil
        }
    }

    var body: some View {
        DetailRow(title: "API key", caption: caption) {
            HStack(spacing: 7) {
                if let console = provider.consoleURL {
                    SettingsButton(title: "Get a Key", symbol: "arrow.up.forward") {
                        NSWorkspace.shared.open(console)
                    }
                }

                SettingsButton(
                    title: model.keySource == .none ? "Add Key…" : "Change…",
                    isProminent: model.keySource == .none
                ) {
                    entering = true
                }
                .popover(isPresented: $entering, arrowEdge: .bottom) {
                    APIKeyEntry(model: model, dismiss: { entering = false })
                }
            }
        }
    }
}

private struct APIKeyEntry: View {
    @Bindable var model: IntelligenceViewModel
    let dismiss: () -> Void

    @FocusState private var focused: Bool

    private var canSave: Bool {
        !model.keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.keySource == .none ? "Add \(model.subject.name) key" : "Replace \(model.subject.name) key")
                .font(.system(size: 12, weight: .semibold))

            HStack(spacing: 7) {
                FieldChrome(isFocused: focused) {
                    SecureField("Paste your key…", text: $model.keyDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5, design: .monospaced))
                        .frame(width: 240)
                        .focused($focused)
                        .onSubmit { save() }
                }

                SettingsButton(title: "Save", isProminent: true) { save() }
                    .disabled(!canSave)
            }

            if let keyError = model.keyError {
                SettingsNotice(symbol: "exclamationmark.triangle.fill", text: keyError)
                    .frame(maxWidth: 300, alignment: .leading)
            }
        }
        .padding(14)
        .onAppear { focused = true }
    }

    private func save() {
        guard canSave else { return }
        model.saveKey()
        if model.keyError == nil {
            dismiss()
        }
    }
}

private struct ModelControl: View {
    @Bindable var model: IntelligenceViewModel

    @FocusState private var customFieldFocused: Bool

    var body: some View {
        Group {
            DetailRow(title: "Model") {
                menu
            }
            .settingsAnchor("provider.model")

            if model.isEditingCustomModel {
                RowSeparator()

                DetailRow(caption: "Type the ID exactly as the provider spells it.", layout: .stacked) {
                    HStack(spacing: 7) {
                        FieldChrome(isFocused: customFieldFocused) {
                            TextField("model-id", text: $model.customModelDraft)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11.5, design: .monospaced))
                                .focused($customFieldFocused)
                                .onSubmit { model.applyCustomModel() }
                        }
                        SettingsButton(title: "Apply", isProminent: true) { model.applyCustomModel() }
                    }
                    .onAppear { customFieldFocused = true }
                }
            }

            if let notice = model.modelCatalogNotice {
                RowSeparator()

                DetailRow(layout: .stacked) {
                    SettingsNotice(symbol: "exclamationmark.triangle.fill", text: notice)
                }
            }
        }
    }

    private var catalogModels: [String] {
        let suggested = Set(model.subject.suggestedModels.map(\.id))
        return model.availableModels.filter { !suggested.contains($0) }
    }

    private var menu: some View {
        Menu {
            if !model.subject.suggestedModels.isEmpty {
                Section("Suggested") {
                    ForEach(model.subject.suggestedModels) { suggestion in
                        item(id: suggestion.id, title: Text(verbatim: suggestion.id))
                    }
                }
            }

            if !catalogModels.isEmpty {
                Section(model.subject.isLocal ? "Pulled locally" : "Available to this key") {
                    ForEach(catalogModels, id: \.self) { id in
                        item(id: id, title: Text(verbatim: id))
                    }
                }
            }

            Divider()
            Button("Enter model ID…") { model.beginCustomModelEntry() }
        } label: {
            MenuChrome {
                label
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var label: some View {
        if model.selectedModel.isEmpty {
            Text("Choose a model")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
        } else {
            Text(verbatim: model.selectedModel)
                .font(.system(size: 11.5, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private func item(id: String, title: Text) -> some View {
        Button {
            model.selectModel(id)
        } label: {
            if id == model.selectedModel {
                HStack {
                    Image(systemName: "checkmark")
                    title
                }
            } else {
                title
            }
        }
    }
}

// MARK: - Bring your own endpoint

private struct CustomProviderEditor: View {
    @Bindable var model: IntelligenceViewModel

    @FocusState private var focus: Field?

    private enum Field { case name, url }

    private var isEditing: Bool {
        guard let draft = model.customDraft else { return false }
        return model.providers.contains { $0.id == draft.id }
    }

    var body: some View {
        SubPageHeader(backTitle: "Back") { model.cancelCustomProvider() }

        SettingsPageHeader(
            title: isEditing ? "Edit endpoint" : "Custom endpoint",
            caption: "Connect any server that uses the OpenAI chat API, usually a base URL ending in /v1."
        )

        SettingsCard {
            DetailRow(title: "Name", layout: .stacked) {
                FieldChrome(isFocused: focus == .name) {
                    TextField("My server", text: $model.customName)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.secondary)
                        .focused($focus, equals: .name)
                }
            }

            RowSeparator()

            DetailRow(title: "Base URL", layout: .stacked) {
                FieldChrome(isFocused: focus == .url) {
                    TextField(text: $model.customBaseURL) {
                        Text(verbatim: "http://localhost:8000/v1")
                    }
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5, design: .monospaced))
                        .focused($focus, equals: .url)
                        .onSubmit { model.commitCustomProvider() }
                }
            }

            RowSeparator()

            DetailRow(layout: .stacked) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        SettingsButton(title: isEditing ? "Save" : "Add", isProminent: true) {
                            model.commitCustomProvider()
                        }
                        .disabled(!model.canCommitCustomProvider)

                        SettingsButton(title: "Cancel") { model.cancelCustomProvider() }
                    }

                    if let error = model.customError {
                        SettingsNotice(symbol: "exclamationmark.triangle.fill", text: error)
                    }
                }
            }
        }
        .padding(.top, 6)
        .onAppear { focus = .name }
    }
}

// MARK: - Tools

private struct AgentToolsPage: View {
    @Bindable var model: IntelligenceViewModel

    var body: some View {
        if let inspected = model.inspectedProvider {
            SubPageHeader(verbatimBackTitle: inspected.name) { model.leaveTools() }
        } else {
            SubPageHeader(backTitle: "Assistant") { model.leaveTools() }
        }

        SettingsPageHeader(
            title: "Tools",
            caption: "What \(model.subject.name) may do in the browser. Every tool takes a share of the model’s context."
        )

        if let warning = model.toolWarning {
            StatusRow(
                tint: Theme.warning,
                symbol: "exclamationmark",
                title: "More tools than recommended",
                verbatimCaption: warning
            ) {
                SettingsButton(title: "Use Recommended", tint: Theme.warning) {
                    model.resetToolsToRecommended()
                }
            }
            .padding(.top, 6)
        } else if !model.isUsingRecommendedTools {
            StatusRow(
                tint: Color(nsColor: .systemGray),
                symbol: "slider.horizontal.3",
                title: "Custom tool set",
                caption: "You’ve changed which tools \(model.subject.name) may use."
            ) {
                SettingsButton(title: "Reset") {
                    model.resetToolsToRecommended()
                }
            }
            .padding(.top, 6)
        }

        ForEach(AgentToolDescriptor.Category.allCases, id: \.self) { category in
            let tools = AgentToolCatalog.descriptors(in: category)
            SettingsSection(title: category.title, symbol: Self.symbol(for: category)) {
                ForEach(tools) { tool in
                    DetailRow(title: tool.title, caption: tool.summary) {
                        SettingsToggle(Binding(
                            get: { model.isToolEnabled(tool.id) },
                            set: { model.setTool(tool.id, enabled: $0) }
                        ))
                    }

                    if tool.id != tools.last?.id {
                        RowSeparator()
                    }
                }
            }
        }

    }

    private static func symbol(for category: AgentToolDescriptor.Category) -> String {
        switch category {
        case .research:
            "magnifyingglass"
        case .page:
            "cursorarrow.click"
        case .tabs:
            "square.on.square"
        case .media:
            "play.rectangle"
        }
    }
}

// MARK: - Readiness

enum ProviderReadiness: Equatable {
    case ready(String)
    case needsKey
    case notRunning(String)
    case checking
    case unsupported(String)

    var level: StatusLevel {
        switch self {
        case .ready:
            .ready
        case .needsKey, .notRunning, .unsupported:
            .attention
        case .checking:
            .idle
        }
    }
}
