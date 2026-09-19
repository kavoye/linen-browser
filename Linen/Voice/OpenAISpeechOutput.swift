// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

@MainActor
final class OpenAISpeechOutput: SpeechOutput {
    var isMuted = false
    var onSpeakingChange: ((Bool) -> Void)?
    var onFailure: (() -> Void)?
    private let client: OpenAIVoiceClient
    private let playback: any StreamingSpeechPlaying
    private var pending: [String] = []
    private var task: Task<Void, Never>?
    private var generation = 0

    init(client: OpenAIVoiceClient, playback: any StreamingSpeechPlaying = OpenAIPCMPlayback()) {
        self.client = client
        self.playback = playback
    }

    func speak(_ text: String) {
        guard !isMuted, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard text.unicodeScalars.count + pending.reduce(0, { $0 + $1.unicodeScalars.count }) <= 100_000 else {
            onFailure?()
            return
        }
        pending += Self.chunks(text)
        guard task == nil else { return }
        onSpeakingChange?(true)
        let generation = generation
        task = Task { [weak self] in
            guard let self else { return }
            do {
                while !pending.isEmpty {
                    try Task.checkCancellation()
                    let text = pending.removeFirst()
                    for try await bytes in client.speech(text) {
                        try Task.checkCancellation()
                        guard self.generation == generation else { return }
                        try await playback.append(bytes)
                        try Task.checkCancellation()
                        guard self.generation == generation else { return }
                        onSpeakingChange?(true)
                    }
                    try Task.checkCancellation()
                    guard self.generation == generation else { return }
                    try await playback.finish()
                }
                guard self.generation == generation else { return }
                task = nil
                playback.stop()
                onSpeakingChange?(false)
            } catch {
                guard self.generation == generation else { return }
                task = nil
                pending.removeAll()
                playback.stop()
                onSpeakingChange?(false)
                if !Task.isCancelled {
                    onFailure?()
                }
            }
        }
    }

    func stopSpeaking() {
        generation &+= 1
        task?.cancel()
        task = nil
        pending.removeAll()
        playback.stop()
        onSpeakingChange?(false)
    }

    nonisolated static func chunks(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var count = 0
        for character in text {
            let size = character.unicodeScalars.count
            if count + size > 1_000, !current.isEmpty {
                result.append(current)
                current = ""
                count = 0
            }
            current.append(character)
            count += size
            if count >= 600, ".!?\n".contains(character) {
                result.append(current)
                current = ""
                count = 0
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }
}

@MainActor
final class ProviderSpeechOutput: SpeechOutput {
    private var output: any SpeechOutput
    private var generation = 0
    var isMuted = false {
        didSet { output.isMuted = isMuted }
    }
    var onSpeakingChange: ((Bool) -> Void)?

    init(output: any SpeechOutput = AppleSpeechOutput()) {
        self.output = output
        use(output)
    }

    func use(_ next: any SpeechOutput) {
        generation &+= 1
        output.onSpeakingChange = nil
        output.stopSpeaking()
        output = next
        output.isMuted = isMuted
        let generation = generation
        output.onSpeakingChange = { [weak self] speaking in
            guard let self, self.generation == generation else { return }
            onSpeakingChange?(speaking)
        }
        onSpeakingChange?(false)
    }

    func speak(_ text: String) {
        output.speak(text)
    }

    func stopSpeaking() {
        output.stopSpeaking()
    }
}
