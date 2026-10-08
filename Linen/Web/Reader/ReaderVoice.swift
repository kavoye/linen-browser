// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

@MainActor
final class ReaderVoice: SpeechOutput {
    private let provider = ProviderSpeechOutput()
    private let makeSystemOutput: () -> any SpeechOutput
    private var makeAssistantOutput: (() -> any SpeechOutput)?
    private var usesAssistant: Bool?

    var isMuted: Bool {
        get { provider.isMuted }
        set { provider.isMuted = newValue }
    }

    var onSpeakingChange: ((Bool) -> Void)? {
        get { provider.onSpeakingChange }
        set { provider.onSpeakingChange = newValue }
    }

    init(makeSystemOutput: @escaping () -> any SpeechOutput = { AppleSpeechOutput() }) {
        self.makeSystemOutput = makeSystemOutput
    }

    func setAssistantOutput(_ make: (() -> any SpeechOutput)?) {
        makeAssistantOutput = make
        usesAssistant = nil
    }

    func speak(_ text: String) {
        let assistant = makeAssistantOutput != nil
        if assistant != usesAssistant {
            usesAssistant = assistant
            if let makeAssistantOutput {
                provider.use(makeAssistantOutput())
            } else {
                provider.use(makeSystemOutput())
            }
        }
        provider.speak(text)
    }

    func stopSpeaking() {
        provider.stopSpeaking()
    }
}
