// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct OpenAISettingsSection: View {
    let providerID: String
    let modelID: String
    let onSave: (OpenAIResponseSettings) -> Void
    let onOpen: (OpenAISettingsPage) -> Void

    @State private var options = OpenAIResponseSettings()
    @State private var loaded = false

    var body: some View {
        SettingsSection(title: "OpenAI", symbol: "sparkles", footnote: "Supported models can search the web, create images, and analyze data. OpenAI charges for API use.", accessory: {
            Menu {
                Button("Developer settings…") { onOpen(.developer) }
            } label: { Image(systemName: "ellipsis") }
            .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("More OpenAI settings")
        }) {
            if OpenAIModelSupport.verbosity(modelID) {
                DetailRow(title: "Reply length") {
                    Picker("Reply length", selection: savedOptions.verbosity) {
                        Text("Short").tag("low")
                        Text("Medium").tag("medium")
                        Text("Long").tag("high")
                    }.labelsHidden()
                }
                .settingsAnchor("openai.replyLength")
                RowSeparator()
            }
            DrillInRow(title: "Connections", symbol: "link", caption: "Connect services the assistant can use.") { onOpen(.connections) }
                .settingsAnchor("openai.connections")
            RowSeparator()
            DrillInRow(title: "Data and privacy", symbol: "hand.raised", caption: "Choose whether you can retrieve replies through the OpenAI API.") { onOpen(.privacy) }
                .settingsAnchor("openai.privacy")

        }
        .settingsAnchor("openai.developer")
        .disabled(!loaded)
        .task {
            guard !loaded else { return }
            options = OpenAISettingsStore.load(providerID: providerID)
            loaded = true
        }
    }

    private var savedOptions: Binding<OpenAIResponseSettings> {
        Binding(get: { options }, set: { value in
            options = value
            onSave(value)
        })
    }
}

enum OpenAISettingsPage: Hashable {
    case connections, privacy, developer

    init?(anchor: String) {
        if anchor.hasPrefix("openai.connections") {
            self = .connections
        } else if anchor.hasPrefix("openai.privacy") {
            self = .privacy
        } else if anchor.hasPrefix("openai.developer") {
            self = .developer
        } else {
            return nil
        }
    }

    init?(slug: String) {
        switch slug {
        case "connections":
            self = .connections
        case "privacy":
            self = .privacy
        case "developer":
            self = .developer
        default:
            return nil
        }
    }

    var slug: String {
        switch self {
        case .connections:
            "connections"
        case .privacy:
            "privacy"
        case .developer:
            "developer"
        }
    }

    func subpageTitle(_ slug: String?) -> LocalizedStringResource? {
        switch (self, slug) {
        case (.developer, "api-json"):
            "API JSON"
        case (.developer, "voice-models"):
            "Voice models"
        case (.connections, "add"):
            "Add connection"
        case (.connections, "edit"):
            "Edit connection"
        default:
            nil
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .connections:
            "Connections"
        case .privacy:
            "Data and privacy"
        case .developer:
            "Developer settings"
        }
    }
}

struct OpenAISettingsPageView: View {
    @Bindable var model: IntelligenceViewModel
    let page: OpenAISettingsPage

    @Environment(\.settingsRouter) private var router
    @State private var options = OpenAIResponseSettings()
    @State private var loaded = false

    private var base: [String] {
        model.path
    }

    private var subpageTitle: LocalizedStringResource? {
        guard router.path.starts(with: base) else { return nil }
        return page.subpageTitle(router.path.dropFirst(base.count).first)
    }

    var body: some View {
        if let subpageTitle {
            SubPageHeader(backTitle: page.title) { router.back(to: base) }
            SettingsPageHeader(title: subpageTitle)
        } else {
            if let inspected = model.inspectedProvider {
                SubPageHeader(verbatimBackTitle: inspected.name) { model.leaveTools() }
            } else {
                SubPageHeader(backTitle: "Assistant") { model.leaveTools() }
            }
            SettingsPageHeader(title: page.title)
        }

        VStack(alignment: .leading, spacing: 20) {
            if loaded {
                switch page {
                case .connections:
                    OpenAIMCPSettingsView(providerID: model.subject.id, servers: savedOptions.mcpServers, base: base)
                        .id("mcp:\(model.subject.id):\(model.credentialRevision)")
                case .privacy:
                    OpenAIPrivacySettings(options: savedOptions)
                case .developer:
                    OpenAIDeveloperSettings(options: savedOptions, base: base)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            guard !loaded else { return }
            options = OpenAISettingsStore.load(providerID: model.subject.id)
            loaded = true
        }
    }

    private var savedOptions: Binding<OpenAIResponseSettings> {
        Binding(get: { options }, set: { value in
            options = value
            model.saveOpenAISettings(value)
        })
    }
}

private struct OpenAIPrivacySettings: View {
    @Binding var options: OpenAIResponseSettings

    var body: some View {
        Text("Linen saves chat history on this Mac. Your messages are still sent to OpenAI to generate replies.")
            .font(.callout).foregroundStyle(.secondary)
        SettingsCard {
            DetailRow(title: "Keep replies in my OpenAI account", caption: "OpenAI keeps a copy that you can retrieve through its API. Linen’s chat history doesn’t need it.") {
                SettingsToggle($options.store)
            }
            .settingsAnchor("openai.privacy")
        }
        Text("Turning this off affects new replies. It does not delete earlier copies or change OpenAI’s other data-retention policies.")
            .font(.caption).foregroundStyle(.secondary)
    }
}
