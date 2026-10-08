// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct VoiceSettings: View {
    let coordinator: AppCoordinator
    @Bindable var preferences: VoicePreferences
    let onOpenAssistant: () -> Void

    @State private var options = OpenAIVoiceSettings()
    @State private var talk = ActivationSettings.talk
    @State private var recording: String?
    @State private var writesOwnStyle = false

    private var canUseOpenAI: Bool {
        coordinator.canUseOpenAIVoice
    }

    private var conversationIsOn: Bool {
        canUseOpenAI && preferences.allowsConversation
    }

    var body: some View {
        SettingsPageHeader(
            title: "Voice",
            caption: "Choose how Linen listens and speaks. Voices on this Mac are free. OpenAI voices are billed to your API key."
        )

        if !canUseOpenAI {
            OpenAIKeyNotice(onOpenAssistant: onOpenAssistant)
        }

        SettingsSection(title: "Dictation", symbol: "mic", accessory: {
            VoiceCostBadge(isBilled: coordinator.dictatesWithOpenAI)
        }) {
            OptionList(
                options: [
                    .init(value: VoiceEngine.device, label: "On this Mac",
                          caption: "Recognizes your speech on this Mac at no cost."),
                    .init(value: VoiceEngine.openAI, label: "OpenAI",
                          caption: "Recognizes names and mixed languages better. Billed for each minute you speak."),
                ],
                selection: coordinator.dictatesWithOpenAI ? .openAI : .device,
                onSelect: { preferences.dictation = $0 }
            )
            .disabled(!canUseOpenAI)
            .settingsAnchor("voice.dictation")

            RowSeparator()

            DetailRow(
                title: "Push to talk",
                caption: "Hold the shortcut to speak, then release it to send."
            ) {
                ShortcutRecorder(
                    id: "talk",
                    recording: $recording,
                    shortcut: talk,
                    defaultShortcut: ActivationSettings.defaultTalk
                ) { recorded in
                    talk = recorded
                    ActivationSettings.talk = recorded
                    coordinator.reloadActivation()
                }
            }
            .settingsAnchor("voice.talk")
        }

        SettingsSection(
            title: "Reading aloud",
            symbol: "speaker.wave.2",
            footnote: "Reader uses the same voice. To add better voices to this Mac, download them in [System Settings](x-apple.systempreferences:com.apple.preference.universalaccess?TextToSpeech).",
            accessory: { VoiceCostBadge(isBilled: coordinator.readsWithOpenAI) }
        ) {
            DetailRow(title: "Speak answers automatically", caption: "Read each answer aloud when it finishes.") {
                SettingsToggle($preferences.speaksAnswers)
            }
            .settingsAnchor("voice.readAloud")

            RowSeparator()

            OptionList(
                options: [
                    .init(value: VoiceEngine.device, label: "On this Mac",
                          caption: "Uses the best voice installed on this Mac at no cost."),
                    .init(value: VoiceEngine.openAI, label: "OpenAI",
                          caption: "Sounds more natural. Billed for each answer read aloud."),
                ],
                selection: coordinator.readsWithOpenAI ? .openAI : .device,
                onSelect: { preferences.reading = $0 }
            )
            .disabled(!canUseOpenAI)
            .settingsAnchor("voice.reading")

            if coordinator.readsWithOpenAI {
                RowSeparator()

                voiceRow(selection: saved.voice)
                    .settingsAnchor("voice.readingVoice")

                RowSeparator()

                DetailRow(title: "Speed") {
                    SegmentedControl(
                        items: SpeakingSpeed.allCases.map { .init(value: $0, label: $0.label) },
                        selection: SpeakingSpeed.nearest(to: options.speed),
                        onSelect: { saved.speed.wrappedValue = $0.rawValue }
                    )
                }
                .settingsAnchor("voice.readingSpeed")

                if !conversationIsOn {
                    RowSeparator()
                    speakingStyle
                }
            }
        }

        SettingsSection(title: "Conversation", symbol: "waveform", accessory: {
            if conversationIsOn {
                VoiceCostBadge(isBilled: true)
            }
        }) {
            DetailRow(
                title: "Voice conversation",
                caption: "Talk back and forth with the assistant. Billed for each minute a conversation is open."
            ) {
                SettingsToggle(Binding(
                    get: { conversationIsOn },
                    set: { preferences.allowsConversation = $0 }
                ))
                .disabled(!canUseOpenAI)
            }
            .settingsAnchor("voice.conversation")

            if conversationIsOn {
                RowSeparator()

                voiceRow(selection: saved.conversationVoice, conversation: true)
                    .settingsAnchor("voice.conversationVoice")

                RowSeparator()
                speakingStyle
            }
        }
        .onChange(of: recording) { _, listening in
            coordinator.setActivationSuspended(listening != nil)
        }
        .task(id: coordinator.openAIVoiceProviderID) {
            guard let providerID = coordinator.openAIVoiceProviderID else { return }
            options = OpenAISettingsStore.load(providerID: providerID).voice
            writesOwnStyle = SpeakingStyle(instructions: options.instructions) == .custom
        }
        .onDisappear { coordinator.stopVoicePreview() }
    }

    private func voiceRow(selection: Binding<String>, conversation: Bool = false) -> some View {
        DetailRow(title: "Voice") {
            HStack(spacing: 6) {
                IconButton(
                    symbol: coordinator.previewingVoice == selection.wrappedValue ? "stop.fill" : "play.fill",
                    help: "Play a sample. Uses your OpenAI API key."
                ) {
                    coordinator.previewOpenAIVoice(selection.wrappedValue)
                }
                OpenAIVoicePicker(selection: selection, conversation: conversation)
                    .fixedSize()
            }
        }
    }

    private var styleSelection: SpeakingStyle {
        writesOwnStyle ? .custom : SpeakingStyle(instructions: options.instructions)
    }

    @ViewBuilder
    private var speakingStyle: some View {
        DetailRow(title: "Style") {
            SegmentedControl(
                items: SpeakingStyle.allCases.map { .init(value: $0, label: $0.label) },
                selection: styleSelection,
                onSelect: { style in
                    writesOwnStyle = style == .custom
                    if let instructions = style.instructions {
                        saved.instructions.wrappedValue = instructions
                    }
                }
            )
        }
        .settingsAnchor("voice.speakingStyle")

        if styleSelection == .custom {
            RowSeparator()

            DetailRow(caption: "For example, speak slowly or keep replies brief.", layout: .stacked) {
                TextField("Speaking style", text: saved.instructions, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var saved: Binding<OpenAIVoiceSettings> {
        Binding(get: { options }, set: { value in
            var value = value
            value.instructions = String(value.instructions.prefix(2_000))
            options = value
            guard let providerID = coordinator.openAIVoiceProviderID else { return }
            var stored = OpenAISettingsStore.load(providerID: providerID)
            stored.voice = value
            OpenAISettingsStore.save(stored, providerID: providerID)
            coordinator.configureVoice()
        })
    }
}

private struct VoiceCostBadge: View {
    let isBilled: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isBilled {
                StatusDot(.attention)
                Text("OpenAI · Billed")
            } else {
                StatusDot(.ready)
                Text("Free")
            }
        }
        .font(Theme.Font.label)
        .foregroundStyle(.secondary)
        .fixedSize()
    }
}

private struct OpenAIKeyNotice: View {
    let onOpenAssistant: () -> Void

    var body: some View {
        SettingsCard {
            StatusRow(
                tint: Theme.metaInk,
                symbol: "key",
                title: "OpenAI voices need an OpenAI API key",
                caption: "Add an OpenAI API key in Assistant. The assistant can still use a different provider."
            ) {
                SettingsButton(title: "Open Assistant…") { onOpenAssistant() }
            }
        }
    }
}

private enum SpeakingSpeed: Double, CaseIterable {
    case slower = 0.75
    case normal = 1
    case faster = 1.25
    case fastest = 1.5

    var label: LocalizedStringResource {
        switch self {
        case .slower:
            "Slower"
        case .normal:
            "Normal"
        case .faster:
            "Faster"
        case .fastest:
            "Fastest"
        }
    }

    static func nearest(to speed: Double) -> SpeakingSpeed {
        allCases.min { abs($0.rawValue - speed) < abs($1.rawValue - speed) } ?? .normal
    }
}

private enum SpeakingStyle: CaseIterable {
    case natural
    case calm
    case brief
    case custom

    init(instructions: String) {
        self = Self.allCases.first { $0.instructions == instructions } ?? .custom
    }

    var label: LocalizedStringResource {
        switch self {
        case .natural:
            "Natural"
        case .calm:
            "Calm"
        case .brief:
            "Brief"
        case .custom:
            LocalizedStringResource("voice.style.custom", defaultValue: "Custom")
        }
    }

    var instructions: String? {
        switch self {
        case .natural:
            "Speak clearly and naturally."
        case .calm:
            "Speak calmly and warmly, at a relaxed pace."
        case .brief:
            "Speak briskly. Keep it short and get to the point."
        case .custom:
            nil
        }
    }
}
