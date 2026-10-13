// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

nonisolated enum VoiceEngine: String, CaseIterable, Identifiable, Sendable {
    case device
    case openAI

    var id: Self {
        self
    }
}

@MainActor
@Observable
final class VoicePreferences {
    static let shared = VoicePreferences()
    nonisolated static let didChange = Notification.Name("VoicePreferences.didChange")

    var dictation: VoiceEngine {
        didSet { save(dictation.rawValue, Keys.dictation) }
    }

    var reading: VoiceEngine {
        didSet { save(reading.rawValue, Keys.reading) }
    }

    var speaksAnswers: Bool {
        didSet { save(!speaksAnswers, Keys.muted) }
    }

    var allowsConversation: Bool {
        didSet { save(allowsConversation, Keys.conversation) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let dictation = "voice.dictationEngine"
        static let reading = "voice.readingEngine"
        static let muted = "speech.muted"
        static let conversation = "voice.allowsConversation"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        dictation = defaults.string(forKey: Keys.dictation).flatMap(VoiceEngine.init) ?? .device
        reading = defaults.string(forKey: Keys.reading).flatMap(VoiceEngine.init) ?? .device
        speaksAnswers = !(defaults.object(forKey: Keys.muted) as? Bool ?? true)
        allowsConversation = defaults.bool(forKey: Keys.conversation)
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
