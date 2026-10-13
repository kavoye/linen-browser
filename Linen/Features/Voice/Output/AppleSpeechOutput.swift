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

    /// Call from synchronous app launch: the system voice lookup forces a sync
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
    private var queued: [AVSpeechUtterance] = []
    private var spokenLocation = 0

    var isMuted = false
    var onSpeakingChange: ((Bool) -> Void)?
    private var rate: Float = 1

    init() {
        let watcher = SpeakingWatcher { [weak self] utterance, event in
            Task { @MainActor in
                self?.utteranceChanged(utterance.value, event)
            }
        }
        self.watcher = watcher
        synthesizer.delegate = watcher
    }

    func speak(_ text: String) {
        guard !isMuted else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AppleSpeechVoiceCatalog.shared.voice
        utterance.rate = min(AVSpeechUtteranceDefaultSpeechRate * rate, AVSpeechUtteranceMaximumSpeechRate)
        if queued.isEmpty {
            spokenLocation = 0
        }
        queued.append(utterance)
        synthesizer.speak(utterance)
    }

    func setRate(_ rate: Float) {
        guard rate != self.rate else { return }
        self.rate = rate
        speakRemainderAtRate()
    }

    func stopSpeaking() {
        let wasSpeaking = !queued.isEmpty
        cancelQueue()
        if wasSpeaking {
            onSpeakingChange?(false)
        }
    }

    private func cancelQueue() {
        queued.removeAll()
        spokenLocation = 0
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func speakRemainderAtRate() {
        guard let current = queued.first else { return }
        let remainder = (current.speechString as NSString).substring(from: min(spokenLocation, current.speechString.utf16.count))
        let texts = [remainder] + queued.dropFirst().map(\.speechString)
        cancelQueue()
        texts.forEach(speak)
    }

    private func utteranceChanged(_ utterance: AVSpeechUtterance, _ event: SpeakingWatcher.Event) {
        guard let index = queued.firstIndex(where: { $0 === utterance }) else { return }
        switch event {
        case .started:
            spokenLocation = 0
            onSpeakingChange?(true)
        case .word(let location):
            if index == 0 {
                spokenLocation = location
            }
        case .ended:
            queued.remove(at: index)
            if index == 0 {
                spokenLocation = 0
            }
            onSpeakingChange?(!queued.isEmpty)
        }
    }
}

private nonisolated struct UtteranceBox: @unchecked Sendable {
    let value: AVSpeechUtterance
}

private nonisolated final class SpeakingWatcher: NSObject, AVSpeechSynthesizerDelegate {
    enum Event: Sendable {
        case started
        case word(Int)
        case ended
    }

    private let onChange: @Sendable (UtteranceBox, Event) -> Void

    init(onChange: @escaping @Sendable (UtteranceBox, Event) -> Void) {
        self.onChange = onChange
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        onChange(UtteranceBox(value: utterance), .started)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange,
                           utterance: AVSpeechUtterance) {
        onChange(UtteranceBox(value: utterance), .word(characterRange.location))
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onChange(UtteranceBox(value: utterance), .ended)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onChange(UtteranceBox(value: utterance), .ended)
    }
}
