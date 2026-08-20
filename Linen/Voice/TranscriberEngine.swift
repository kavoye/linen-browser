// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AVFAudio

struct TranscriptUpdate: Sendable, Equatable {
    var text: String
    var isFinal: Bool
}

@MainActor
protocol TranscriberEngine: AnyObject {
    var bestFormat: AVAudioFormat? { get }
    func prepare() async throws
    func startSession(input: AsyncStream<CapturedAudio>) -> AsyncThrowingStream<TranscriptUpdate, Error>
    func finishSession() async throws
}
