// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Observation
import SwiftUI

struct AssistantSettings: View {
    @Bindable var model: IntelligenceViewModel
    let coordinator: AppCoordinator
    @Environment(\.settingsHighlight) private var highlight

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
            case .grants:
                AssistantGrantsPage(policy: coordinator.browser.context.actionPolicy, onBack: { model.showOverview() })
            }
        }
        .task { await model.onAppear() }
        .onChange(of: highlight, initial: true) { _, anchor in
            guard let anchor else { return }
            if anchor == "provider.connected" || anchor == "privacy.assistant" || anchor.hasPrefix("assistant.") {
                model.showOverview()
            } else if anchor.hasPrefix("provider.") {
                model.open(model.selected)
                if anchor == "provider.tools" { model.showTools() }
            } else if anchor.hasPrefix("openai."),
                      let provider = model.providers.first(where: { $0.adapter == .openAIResponses }) {
                model.open(provider)
            }
        }
    }
}

// MARK: - Who answers

private struct AssistantOverview: View {
    @Bindable var model: IntelligenceViewModel
    let coordinator: AppCoordinator

    var body: some View {
        SettingsPageHeader(title: "Assistant")

        AnsweringNotice(model: model, coordinator: coordinator)

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
        .padding(.top, 6)

        BehaviourSection(settings: coordinator.settings)

        AssistantExecutionSettings()

        SettingsSection(title: "Acting on websites", symbol: "hand.raised") {
            DrillInRow(
                title: "Allowed without asking",
                detail: AssistantGrantsPage.summary(for: coordinator.browser.context.actionPolicy)
            ) {
                model.showGrants()
            }
            .settingsAnchor("privacy.assistant")
        }

        Footnote(AIDisclosure.settingsCaption)
    }
}

private struct AnsweringNotice: View {
    @Bindable var model: IntelligenceViewModel
    let coordinator: AppCoordinator

    private var active: Provider? {
        coordinator.activeProvider
    }

    var body: some View {
        if active?.id == model.selectedID {
            EmptyView()
        } else {
            SettingsCard {
                state
            }
            .padding(.top, 6)
        }
    }

    @ViewBuilder
    private var state: some View {
        if let active {
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
}

private struct BehaviourSection: View {
    @Bindable var settings: BrowserSettings

    var body: some View {
        SettingsSection(title: "Links", symbol: "link") {
            DetailRow(
                title: "Summarize a link on hover",
                caption: "Hold Shift while pointing at a link to get a summary before opening it."
            ) {
                SettingsToggle($settings.peeksAtLinks)
            }
            .settingsAnchor("assistant.linkPeek")
        }
    }
}

private struct ThinkingSection: View {
    @Bindable var model: IntelligenceViewModel

    var body: some View {
        SettingsSection(title: "Thinking", symbol: "brain") {
            OptionList(
                options: model.availableEfforts.map {
                    .init(value: $0, label: $0.label, caption: $0.caption)
                },
                selection: model.resolvedEffort,
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

                DrillInChevron()
            }
            .padding(.vertical, 9)
            .settingsRowTarget()
        }
        .buttonStyle(.plain)
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
    private var showsReadiness: Bool {
        readiness.level != .ready
    }

    private var endpoint: String? {
        guard let url = provider.baseURL else { return nil }
        let host = url.host() ?? url.absoluteString
        let port = url.port.map { ":\($0)" } ?? ""
        return host + port + url.path()
    }

    var body: some View {
        SubPageHeader(backTitle: "Assistant", onBack: { model.showOverview() })

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
            if showsReadiness {
                ReadinessRow(model: model)

                if !provider.isOnDevice {
                    RowSeparator()
                }
            }

            if !provider.isOnDevice {
                ModelControl(model: model)

                if let window = model.detectedContextWindow(for: provider) {
                    RowSeparator()
                    DetailRow(
                        title: "Context window",
                        caption: "\(provider.name) reports this for the selected model."
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

            if showsReadiness || !provider.isOnDevice {
                RowSeparator()
            }

            DrillInRow(
                title: "Tools",
                detail: "\(model.enabledToolCount(for: provider)) of \(AgentToolCatalog.configurableIDs.count)"
            ) {
                model.showTools()
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

        if model.supportsReasoningEffort {
            ThinkingSection(model: model)
        }
        if provider.adapter == .openAIResponses {
            OpenAISettingsSection(providerID: provider.id, modelID: model.selectedModel,
                credentialRevision: model.credentialRevision, onSave: model.saveOpenAISettings)
                .id(provider.id)
        }
    }

    @ViewBuilder
    private var endpointRow: some View {
        DetailRow(title: "Endpoint") {
            HStack(spacing: 7) {
                SettingsButton(title: "Edit") { model.editCustomProvider(provider) }
                SettingsButton(title: "Remove…", isDestructive: true, symbol: "trash") {
                    confirmingEndpointRemoval = true
                }
                Tag(provider.adapterLabel)
            }
        }
        .settingsAnchor("provider.endpoint")
        .confirmationDialog(
            "Remove \"\(provider.name)\"?",
            isPresented: $confirmingEndpointRemoval
        ) {
            Button("Remove Endpoint", role: .destructive) {
                model.removeCustomProvider(provider)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Linen removes the endpoint’s name and URL. Nothing changes on the server.")
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
        case .ready:
            EmptyView()

        case .needsKey:
            StatusRow(
                tint: Theme.warning,
                symbol: "key",
                title: "Needs a key",
                caption: "Add an API key to use \(provider.name)."
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
    var help: LocalizedStringResource = "Check this provider again"

    var body: some View {
        IconButton(
            symbol: "arrow.clockwise",
            help: help,
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
        SettingsButton(title: "Remove…", isDestructive: true, symbol: "trash") {
            confirming = true
        }
        .confirmationDialog(
            "Remove the \(model.subject.name) key?",
            isPresented: $confirming
        ) {
            Button("Remove Key", role: .destructive) { model.removeKey() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Linen deletes the key from your Keychain. To use \(model.subject.name) again, add a new key.")
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
                footnote: "Linen saves keys in your Keychain."
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
        DetailRow(title: "API key", caption: caption, controlWidth: nil) {
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

                if !provider.isCustom, model.keySource == .keychain {
                    RemoveKeyButton(model: model)
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
                        .font(Theme.Font.mono)
                        .frame(maxWidth: 240)
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
                HStack(spacing: 7) {
                    menu
                    CatalogRefreshButton(model: model, help: "Check for new models")
                }
            }
            .settingsAnchor("provider.model")

            if model.isEditingCustomModel {
                RowSeparator()

                DetailRow(caption: "Enter the model ID as the provider lists it.", layout: .stacked) {
                    HStack(spacing: 7) {
                        FieldChrome(isFocused: customFieldFocused) {
                            TextField("", text: $model.customModelDraft)
                                .fieldPlaceholder(verbatim: "model-id", isShowing: model.customModelDraft.isEmpty)
                                .textFieldStyle(.plain)
                                .font(Theme.Font.mono)
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
                Picker(selection: chosenModel) {
                    ForEach(model.subject.suggestedModels) { suggestion in
                        Text(verbatim: suggestion.id).tag(suggestion.id)
                    }
                } label: {
                    Text("Suggested")
                }
                .pickerStyle(.inline)
            }

            if !catalogModels.isEmpty {
                Picker(selection: chosenModel) {
                    ForEach(catalogModels, id: \.self) { id in
                        Text(verbatim: id).tag(id)
                    }
                } label: {
                    if model.subject.isLocal {
                        Text("Pulled locally")
                    } else {
                        Text("Available to this key")
                    }
                }
                .pickerStyle(.inline)
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
                .font(Theme.Font.secondary)
                .foregroundStyle(.tertiary)
        } else {
            Text(verbatim: model.selectedModel)
                .font(Theme.Font.mono)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var chosenModel: Binding<String> {
        Binding {
            model.selectedModel
        } set: { id in
            model.selectModel(id)
        }
    }
}

// MARK: - Bring your own endpoint

private struct CustomProviderEditor: View {
    @Bindable var model: IntelligenceViewModel

    @FocusState private var focus: Field?

    private enum Field { case name, url }

    private var isEditing: Bool {
        editedProviderName != nil
    }

    private var editedProviderName: String? {
        guard let draft = model.customDraft else { return nil }
        return model.providers.first { $0.id == draft.id }?.name
    }

    var body: some View {
        if let name = editedProviderName {
            SubPageHeader(verbatimBackTitle: name) { model.cancelCustomProvider() }
        } else {
            SubPageHeader(backTitle: "Assistant") { model.cancelCustomProvider() }
        }

        SettingsPageHeader(
            title: isEditing ? "Edit endpoint" : "Custom endpoint",
            caption: "Connect any server that uses the OpenAI chat API. Its base URL usually ends in /v1."
        )

        SettingsCard {
            DetailRow(title: "Name", layout: .stacked) {
                FieldChrome(isFocused: focus == .name) {
                    TextField("", text: $model.customName)
                        .fieldPlaceholder("My server", isShowing: model.customName.isEmpty)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.secondary)
                        .focused($focus, equals: .name)
                }
            }

            RowSeparator()

            DetailRow(title: "Base URL", layout: .stacked) {
                FieldChrome(isFocused: focus == .url) {
                    TextField("", text: $model.customBaseURL)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.mono)
                        .fieldPlaceholder(
                            verbatim: "http://localhost:8000/v1",
                            isShowing: model.customBaseURL.isEmpty
                        )
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
            SubPageHeader(verbatimBackTitle: inspected.name, onBack: { model.leaveTools() }) {
                resetButton
            }
        } else {
            SubPageHeader(backTitle: "Assistant", onBack: { model.leaveTools() }) {
                resetButton
            }
        }

        SettingsPageHeader(
            title: "Tools",
            caption: "Each tool you turn on uses part of the context window."
        )

        if let warning = model.toolWarning {
            StatusRow(
                tint: Theme.warning,
                symbol: "exclamationmark",
                title: "More tools than recommended",
                verbatimCaption: warning
            ) {
                EmptyView()
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

    @ViewBuilder private var resetButton: some View {
        if model.toolWarning != nil {
            SettingsButton(title: "Use Recommended", tint: Theme.warning) {
                model.resetToolsToRecommended()
            }
        } else if !model.isUsingRecommendedTools {
            SettingsButton(title: "Reset") {
                model.resetToolsToRecommended()
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

private struct AssistantExecutionSettings: View {
    @AppStorage(AgentExecutionPolicy.settingsKey) private var requestLimit = 0

    var body: some View {
        SettingsSection(title: "Long tasks", symbol: "arrow.trianglehead.2.clockwise") {
            DetailRow(title: "Pause after", caption: "Stop a long task after this many model requests. Click Continue to resume it.") {
                Picker("Model requests", selection: $requestLimit) {
                    Text("No limit").tag(0)
                    Text("100 requests").tag(100)
                    Text("250 requests").tag(250)
                    Text("500 requests").tag(500)
                }
                .labelsHidden()
            }
            .settingsAnchor("assistant.pauseAfter")
        }
    }
}
