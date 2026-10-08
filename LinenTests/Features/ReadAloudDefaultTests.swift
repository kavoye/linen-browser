// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@MainActor
struct ReadAloudDefaultTests {
    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: TestDefaults.name("ReadAloudDefaultTests")))
    }

    /// A fresh install says nothing out loud until asked to.
    @Test func aFreshInstallStartsMuted() throws {
        #expect(!VoicePreferences(defaults: try defaults()).speaksAnswers)
    }

    /// The default changed, not anyone's choice: a stored value wins in both
    /// directions.
    @Test func anExplicitChoiceSurvivesTheNewDefault() throws {
        let speaking = try defaults()
        speaking.set(false, forKey: "speech.muted")
        #expect(VoicePreferences(defaults: speaking).speaksAnswers)

        let muted = try defaults()
        muted.set(true, forKey: "speech.muted")
        #expect(!VoicePreferences(defaults: muted).speaksAnswers)
    }

    @Test func aFreshInstallUsesNothingBilled() throws {
        let preferences = VoicePreferences(defaults: try defaults())
        #expect(preferences.dictation == .device)
        #expect(preferences.reading == .device)
        #expect(!preferences.allowsConversation)
    }

    @Test func choicesPersist() throws {
        let store = try defaults()
        let preferences = VoicePreferences(defaults: store)
        preferences.dictation = .openAI
        preferences.reading = .openAI
        preferences.allowsConversation = true

        let reloaded = VoicePreferences(defaults: store)
        #expect(reloaded.dictation == .openAI)
        #expect(reloaded.reading == .openAI)
        #expect(reloaded.allowsConversation)
    }
}
