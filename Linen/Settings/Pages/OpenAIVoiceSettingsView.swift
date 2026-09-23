// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct OpenAIVoiceSettingsView: View {
    @Binding var options: OpenAIVoiceSettings

    var body: some View {
        Text("Choose voices for conversation and reading aloud. Voice features send audio or text to OpenAI.")
            .font(.callout).foregroundStyle(.secondary)
        SettingsSection(title: "Conversation", symbol: "waveform") {
            DetailRow(title: "Voice", caption: "Choose the voice used during conversations.") {
                OpenAIVoicePicker(selection: $options.conversationVoice, conversation: true)
            }
            DetailRow(title: "Speaking style", caption: "For example, speak slowly or keep replies brief.", layout: .stacked) {
                TextField("Speaking style", text: $options.instructions, axis: .vertical)
                    .lineLimit(2...4).textFieldStyle(.roundedBorder)
                    .onChange(of: options.instructions) {
                        if options.instructions.count > 2_000 {
                            options.instructions = String(options.instructions.prefix(2_000))
                        }
                    }
            }
            .settingsAnchor("openai.voice.speakingStyle")
        }
        SettingsSection(title: "Dictation and read aloud", symbol: "speaker.wave.2") {
            DetailRow(title: "Reading voice") { OpenAIVoicePicker(selection: $options.voice) }
                .settingsAnchor("openai.voice.readingVoice")
            RowSeparator()
            DetailRow(title: "Reading speed") {
                Slider(value: $options.speed, in: 0.5...2, step: 0.1).frame(width: 120).accessibilityLabel("Reading speed")
                Text(options.speed, format: .number.precision(.fractionLength(1))).monospacedDigit()
            }
            .settingsAnchor("openai.voice.readingSpeed")
        }
    }
}

private struct OpenAIVoicePicker: View {
    @Binding var selection: String
    var conversation = false

    var body: some View {
        Picker("Voice", selection: $selection) {
            ForEach(voices, id: \.self) { voice in Text(verbatim: voice.capitalized).tag(voice) }
        }.labelsHidden()
    }

    private var voices: [String] {
        let supported = conversation ? ["alloy", "ash", "ballad", "coral", "echo", "sage", "shimmer", "verse", "marin", "cedar"]
            : ["alloy", "ash", "ballad", "coral", "echo", "fable", "onyx", "nova", "sage", "shimmer", "verse", "marin", "cedar"]
        return supported.contains(selection) ? supported : supported + [selection]
    }
}

struct OpenAIVoiceModelEditor: View {
    @Binding var options: OpenAIVoiceSettings
    @State private var transcription = ""
    @State private var speech = ""
    @State private var conversation = ""
    @State private var message: String?

    var body: some View {
        Text("Linen chooses these models unless you enter different IDs for your API setup.")
            .font(.callout).foregroundStyle(.secondary)
        SettingsCard {
            DetailRow(title: "Dictation model", layout: .stacked) { TextField("Model ID", text: $transcription) }
            RowSeparator()
            DetailRow(title: "Read-aloud model", layout: .stacked) { TextField("Model ID", text: $speech) }
            RowSeparator()
            DetailRow(title: "Conversation model", layout: .stacked) { TextField("Model ID", text: $conversation) }
        }.textFieldStyle(.roundedBorder)
        SettingsButton(title: "Save changes", isProminent: true) {
            var candidate = options
            candidate.transcriptionModel = transcription.trimmingCharacters(in: .whitespacesAndNewlines)
            candidate.speechModel = speech.trimmingCharacters(in: .whitespacesAndNewlines)
            candidate.conversationModel = conversation.trimmingCharacters(in: .whitespacesAndNewlines)
            do {
                try candidate.validate()
                _ = try candidate.conversationConfiguration()
                options = candidate
                message = String(localized: "Saved")
            } catch { message = String(localized: "Enter a model name for each voice feature.") }
        }
        if let message {
            Text(message).font(.callout).foregroundStyle(.secondary)
        }
        Color.clear.frame(height: 0).task {
            transcription = options.transcriptionModel
            speech = options.speechModel
            conversation = options.conversationModel
        }
    }
}
