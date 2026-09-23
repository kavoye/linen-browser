// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct OpenAIDeveloperSettings: View {
    @Binding var options: OpenAIResponseSettings
    @State private var showsJSON = false
    @State private var showsVoiceModels = false
    @Environment(\.settingsHighlight) private var highlight

    var body: some View {
        Text("Change these options only if your API setup needs them. Chat and voice work with the defaults.")
            .font(.callout).foregroundStyle(.secondary)
        SettingsSection(title: "API configuration", symbol: "curlybraces") {
            DetailRow(title: "Run commands at OpenAI", caption: "Allow a hosted shell to run commands and create files. Extra charges may apply.") {
                SettingsToggle(Binding(get: { options.hostedTools.contains { $0["type"] == "shell" } }, set: { enabled in
                    var updated = options
                    updated.hostedTools.removeAll { $0["type"] == "shell" }
                    if enabled {
                        updated.hostedTools.append(OpenAIHostedShell.definition)
                    }
                    options = updated
                }))
            }
            .settingsAnchor("openai.developer.runCommands")
            RowSeparator()
            DrillInRow(title: "Voice models", caption: "Override the models used for listening and speech.") { showsVoiceModels = true }
                .settingsAnchor("openai.developer.voiceModels")
            RowSeparator()
            DrillInRow(title: "API JSON", caption: "Edit additional parameters and hosted tool definitions.") { showsJSON = true }
                .settingsAnchor("openai.developer.apiJSON")
        }
        .sheet(isPresented: $showsJSON) {
            OpenAISettingsSheet(title: "API JSON") { OpenAIJSONSettingsEditor(options: $options) }
        }
        .sheet(isPresented: $showsVoiceModels) {
            OpenAISettingsSheet(title: "Voice models") { OpenAIVoiceModelEditor(options: $options.voice) }
        }
        .onChange(of: highlight, initial: true) { _, anchor in
            showsVoiceModels = anchor == "openai.developer.voiceModels"
            showsJSON = anchor == "openai.developer.apiJSON"
        }
    }
}

private struct OpenAIJSONSettingsEditor: View {
    @Binding var options: OpenAIResponseSettings
    @State private var parameters = ""
    @State private var tools = ""
    @State private var error: String?
    @State private var saved = false

    var body: some View {
        Text("Changes apply after you save. Linen manages permissions, model selection, and conversation state.")
            .font(.callout).foregroundStyle(.secondary)
        OpenAIJSONField(title: "Additional response parameters", text: $parameters)
        OpenAIJSONField(title: "Hosted tool definitions", text: $tools)
        if let error {
            Text(error).font(.callout).foregroundStyle(.red)
        }
        HStack {
            SettingsButton(title: "Save changes", isProminent: true, action: save)
            if saved { Text("Saved").font(.callout).foregroundStyle(.secondary) }
        }
        .onChange(of: parameters) { saved = false }
        .onChange(of: tools) { saved = false }
        .task {
            parameters = (try? options.additionalParameters.text()) ?? "{}"
            tools = (try? OpenAIJSON.array(options.hostedTools).text()) ?? "[]"
        }
    }

    private func save() {
        do {
            var candidate = options
            candidate.additionalParameters = try .decode(Data(parameters.utf8))
            guard let array = try OpenAIJSON.decode(Data(tools.utf8)).array else { throw OpenAISettingsError.unsupportedTool }
            candidate.hostedTools = array
            try candidate.validate()
            options = candidate
            error = nil
            saved = true
        } catch {
            self.error = (error as? OpenAISettingsError)?.localizedDescription ?? String(localized: "Check the JSON and try again.")
        }
    }
}

private struct OpenAIJSONField: View {
    let title: LocalizedStringResource
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.callout.weight(.medium))
            TextEditor(text: $text)
                .font(.system(.callout, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(height: 130)
                .background(Theme.Wash.faint, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel(Text(title))
        }
    }
}
