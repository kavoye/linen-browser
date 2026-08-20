// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AVFoundation

@MainActor
final class AppleSpeechOutput: SpeechOutput {
    private let synthesizer = AVSpeechSynthesizer()
    private let voice = AppleSpeechOutput.bestEnglishVoice()
    private var watcher: SpeakingWatcher?

    var isMuted = false
    var onSpeakingChange: ((Bool) -> Void)?

    init() {
        let watcher = SpeakingWatcher { [weak self] speaking in
            Task { @MainActor in
                self?.onSpeakingChange?(speaking)
            }
        }
        self.watcher = watcher
        synthesizer.delegate = watcher
    }

    func speak(_ text: String) {
        guard !isMuted else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private static func bestEnglishVoice() -> AVSpeechSynthesisVoice? {
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        return english.first { $0.quality == .premium }
            ?? english.first { $0.quality == .enhanced }
            ?? english.first
    }
}

private nonisolated final class SpeakingWatcher: NSObject, AVSpeechSynthesizerDelegate {
    private let onChange: @Sendable (Bool) -> Void

    init(onChange: @escaping @Sendable (Bool) -> Void) {
        self.onChange = onChange
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        onChange(true)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onChange(synthesizer.isSpeaking)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onChange(synthesizer.isSpeaking)
    }
}
