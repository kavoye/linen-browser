// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct OpenAISettingsSection: View {
    let providerID: String
    let modelID: String
    var credentialRevision = 0
    let onSave: (OpenAIResponseSettings) -> Void

    @State private var options = OpenAIResponseSettings()
    @State private var loaded = false
    @State private var destination: OpenAISettingsDestination?
    @Environment(\.settingsHighlight) private var highlight

    var body: some View {
        SettingsSection(title: "OpenAI", symbol: "sparkles", footnote: "Supported models can search the web, create images, and analyze data. OpenAI charges for API use.", accessory: {
            Menu {
                Button("Developer settings…") { destination = .developer }
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
            DrillInRow(title: "Voice", symbol: "waveform", caption: "Choose voices for conversation and reading aloud.") { destination = .voice }
                .settingsAnchor("openai.voice")
            RowSeparator()
            DrillInRow(title: "Connections", symbol: "link", caption: "Connect services your assistant can use.") { destination = .connections }
                .settingsAnchor("openai.connections")
            RowSeparator()
            DrillInRow(title: "Data and privacy", symbol: "hand.raised", caption: "Choose whether you can retrieve replies through the OpenAI API.") { destination = .privacy }
                .settingsAnchor("openai.privacy")

        }
        .settingsAnchor("openai.developer")
        .disabled(!loaded)
        .task {
            guard !loaded else { return }
            options = OpenAISettingsStore.load(providerID: providerID)
            loaded = true
        }
        .onChange(of: highlight, initial: true) { _, anchor in
            guard let anchor else { return }
            if anchor.hasPrefix("openai.voice") {
                destination = .voice
            } else if anchor.hasPrefix("openai.connections") {
                destination = .connections
            } else if anchor.hasPrefix("openai.privacy") {
                destination = .privacy
            } else if anchor.hasPrefix("openai.developer") {
                destination = .developer
            }
        }
        .sheet(item: $destination) { page in
            OpenAISettingsSheet(title: page.title) {
                switch page {
                case .voice:
                    OpenAIVoiceSettingsView(options: savedOptions.voice)
                case .connections:
                    OpenAIMCPSettingsView(providerID: providerID, servers: savedOptions.mcpServers)
                        .id("mcp:\(providerID):\(credentialRevision)")
                case .privacy:
                    OpenAIPrivacySettings(options: savedOptions)
                case .developer:
                    OpenAIDeveloperSettings(options: savedOptions)
                }
            }
        }
    }

    private var savedOptions: Binding<OpenAIResponseSettings> {
        Binding(get: { options }, set: { value in
            options = value
            onSave(value)
        })
    }
}

private enum OpenAISettingsDestination: String, Identifiable {
    case voice, connections, privacy, developer
    var id: String {
        rawValue
    }
    var title: LocalizedStringResource {
        switch self {
        case .voice:
            "Voice"
        case .connections:
            "Connections"
        case .privacy:
            "Data and privacy"
        case .developer:
            "Developer settings"
        }
    }
}

struct OpenAISettingsSheet<Content: View>: View {
    let title: LocalizedStringResource
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.title3.weight(.semibold))
                Spacer()
                SettingsButton(title: "Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
            }
        }
        .frame(width: 600, height: 580)
        .background(Theme.windowBackground)
        .environment(\.settingsDescriptionLineLimit, nil)
    }
}

private struct OpenAIPrivacySettings: View {
    @Binding var options: OpenAIResponseSettings

    var body: some View {
        Text("Linen saves chat history on this Mac. Your messages are still sent to OpenAI to generate replies.")
            .font(.callout).foregroundStyle(.secondary)
        SettingsCard {
            DetailRow(title: "Keep replies in my OpenAI account", caption: "Save an extra copy for retrieval through the OpenAI API. You don't need this for Linen's chat history.") {
                SettingsToggle($options.store)
            }
            .settingsAnchor("openai.privacy")
        }
        Text("Turning this off affects new replies. It does not delete earlier copies or change OpenAI's other data-retention policies.")
            .font(.caption).foregroundStyle(.secondary)
    }
}
