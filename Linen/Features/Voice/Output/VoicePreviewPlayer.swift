// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

@Observable
final class VoicePreviewPlayer {
    private(set) var voice: String?
    @ObservationIgnored private var output: OpenAISpeechOutput?

    func play(_ voice: String, line: String, client: OpenAIVoiceClient, onFailure: @escaping () -> Void) {
        let output = OpenAISpeechOutput(client: client)
        output.onSpeakingChange = { [weak self, weak output] speaking in
            guard let self, !speaking, self.output === output else { return }
            self.output = nil
            self.voice = nil
        }
        output.onFailure = onFailure
        self.output = output
        self.voice = voice
        output.speak(line)
    }

    func stop() {
        output?.stopSpeaking()
        output = nil
        voice = nil
    }
}
