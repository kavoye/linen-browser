// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

@MainActor
protocol SpeechOutput: AnyObject {
    var isMuted: Bool { get set }
    var onSpeakingChange: ((Bool) -> Void)? { get set }
    func speak(_ text: String)
    func stopSpeaking()
}
