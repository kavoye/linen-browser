// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@MainActor
@Suite(.serialized)
struct ReadAloudTests {
    @Test
    func readAloudMarksOnlyTheAnswerBeingRead() {
        let coordinator = AppCoordinator()
        let output = ReadAloudSpeech()
        coordinator.speech.use(output)
        let first = UUID()
        let second = UUID()

        coordinator.readAloud("First", id: first)
        #expect(coordinator.speakingAnswerID == first)

        coordinator.readAloud("Second", id: second)
        #expect(coordinator.speakingAnswerID == second)
        #expect(output.spoken == ["First", "Second"])

        coordinator.readAloud("Second", id: second)
        #expect(coordinator.speakingAnswerID == nil)
        #expect(output.spoken == ["First", "Second"])

        coordinator.readAloud("First", id: first)
        output.finish()
        #expect(coordinator.speakingAnswerID == nil)
    }

    @Test
    func lateStopFromThePreviousAnswerKeepsTheNewOne() {
        let coordinator = AppCoordinator()
        let output = ReadAloudSpeech()
        output.reportsStopLate = true
        coordinator.speech.use(output)
        let first = UUID()
        let second = UUID()

        coordinator.readAloud("First", id: first)
        output.start()
        coordinator.readAloud("Second", id: second)
        output.deliverLateStop()
        output.start()
        #expect(coordinator.speakingAnswerID == second)
    }

    @Test
    func muteFollowsEveryWindow() async {
        let preferences = VoicePreferences.shared
        let original = preferences.speaksAnswers
        defer { preferences.speaksAnswers = original }
        let first = AppCoordinator()
        let second = AppCoordinator()

        preferences.speaksAnswers = true
        await settle { !first.speech.isMuted && !second.speech.isMuted }
        #expect(!second.speech.isMuted)

        first.toggleSpeechMute()
        await settle { second.speech.isMuted }
        #expect(first.speech.isMuted)
        #expect(second.speech.isMuted)
    }

    @Test
    func conversationStaysOffUntilAllowed() {
        let preferences = VoicePreferences.shared
        let original = preferences.allowsConversation
        defer { preferences.allowsConversation = original }
        let coordinator = AppCoordinator()

        preferences.allowsConversation = false
        #expect(!coordinator.supportsVoiceConversation)
        coordinator.startVoiceConversation()
        #expect(!coordinator.isVoiceConversationPresented)
    }

    private func settle(_ condition: () -> Bool) async {
        for _ in 0..<100 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
private final class ReadAloudSpeech: SpeechOutput {
    var isMuted = false
    var onSpeakingChange: ((Bool) -> Void)?
    var spoken: [String] = []
    var reportsStopLate = false
    private var lateStop = false

    func speak(_ text: String) {
        guard !isMuted else { return }
        spoken.append(text)
        if !reportsStopLate {
            start()
        }
    }

    func stopSpeaking() {
        if reportsStopLate {
            lateStop = true
        } else {
            onSpeakingChange?(false)
        }
    }

    func start() {
        onSpeakingChange?(true)
    }

    func finish() {
        onSpeakingChange?(false)
    }

    func deliverLateStop() {
        guard lateStop else { return }
        lateStop = false
        onSpeakingChange?(false)
    }
}
