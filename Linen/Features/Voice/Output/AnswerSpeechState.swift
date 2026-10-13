// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

@Observable
final class AnswerSpeechState {
    private(set) var isSpeaking = false
    private(set) var answerID: UUID?
    @ObservationIgnored private var hasStarted = false

    var speakingAnswerID: UUID? {
        isSpeaking ? answerID : nil
    }

    func speakingChanged(_ speaking: Bool) {
        isSpeaking = speaking
        if speaking {
            hasStarted = answerID != nil
        } else if hasStarted {
            answerID = nil
            hasStarted = false
        }
    }

    func begin(_ id: UUID) {
        answerID = id
        hasStarted = false
    }

    func clear() {
        answerID = nil
    }
}
