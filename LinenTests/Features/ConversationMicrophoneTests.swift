// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AVFAudio
import Foundation
import Testing

@testable import Linen

@MainActor
@Suite(.serialized)
struct ConversationMicrophoneTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LINEN_MIC_CAPTURE_TEST"] == "1"), arguments: 0..<3)
    func physicalConversationCaptureDeliversPCM(attempt: Int) async throws {
        let processesVoice = ProcessInfo.processInfo.environment["LINEN_MIC_RAW_ONLY"] != "1"
        try #require(MicrophoneAccess.state == .allowed)
        let capture = AudioCaptureService(conversational: true, processesVoice: processesVoice)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1))
        var startupTicks = 0
        let heartbeat = Task { @MainActor in
            while !Task.isCancelled {
                try await Task.sleep(for: .milliseconds(20))
                startupTicks += 1
            }
        }
        defer { heartbeat.cancel() }
        let started = Date()
        let stream = try await capture.start(targetFormat: format)
        heartbeat.cancel()
        print("LINEN_MIC_STARTUP seconds=\(Date().timeIntervalSince(started)) main_actor_ticks=\(startupTicks)")
        defer { capture.stop() }
        let stop = Task { @MainActor in
            try await Task.sleep(for: .seconds(4))
            capture.stop()
        }
        defer { stop.cancel() }
        var count = 0, frames = 0
        var maximumRMS = 0.0
        for await sample in stream {
            count += 1
            frames += Int(sample.buffer.frameLength)
            maximumRMS = max(maximumRMS, AudioSampleConverter.level(of: sample.buffer) ?? 0)
            let encoded = try OpenAIPCM.encode(sample.buffer)
            #expect(encoded.count == Int(sample.buffer.frameLength) * 2)
        }
        print("LINEN_MIC_CAPTURE attempt=\(attempt) processed=\(processesVoice) echo_cancellation=\(capture.usesEchoCancellation) buffers=\(count) frames=\(frames) peak_rms=\(maximumRMS)")
        #expect(count > 0)
        #expect(frames >= 24_000)
        #expect(maximumRMS > 0, "Capture must deliver actual microphone samples, not only zero-filled buffers.")
    }
}
