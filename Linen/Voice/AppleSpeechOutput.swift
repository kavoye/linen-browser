// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AVFoundation

@MainActor
final class AppleSpeechVoiceCatalog {
    static let shared = AppleSpeechVoiceCatalog()

    private let loadVoices: () -> [AVSpeechSynthesisVoice]
    private var isPrepared = false
    private(set) var voice: AVSpeechSynthesisVoice?

    init(loadVoices: @escaping () -> [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices) {
        self.loadVoices = loadVoices
    }

    /// Call from synchronous app launch: Apple's voice lookup forces a sync
    /// operation internally and warns when entered from a Swift task.
    func prepare() {
        guard !isPrepared else { return }
        let english = loadVoices().filter { $0.language.hasPrefix("en") }
        voice = english.first { $0.quality == .premium }
            ?? english.first { $0.quality == .enhanced }
            ?? english.first
        isPrepared = true
    }
}

@MainActor
final class AppleSpeechOutput: SpeechOutput {
    private let synthesizer = AVSpeechSynthesizer()
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
        utterance.voice = AppleSpeechVoiceCatalog.shared.voice
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
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
