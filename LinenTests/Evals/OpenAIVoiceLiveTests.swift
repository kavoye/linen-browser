// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AVFAudio
import Foundation
import Testing

@testable import Linen

@MainActor
struct OpenAIVoiceLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LINEN_OPENAI_LIVE_CONFIG"] != nil))
    func generatedSpeechTranscribesThroughRealtime() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["LINEN_OPENAI_LIVE_CONFIG"])
        let config = try OpenAIJSON.decode(Data(contentsOf: URL(fileURLWithPath: path)))
        guard config["voice_only"] == true, config["live"] == true else { return }
        let destination = URL(fileURLWithPath: try #require(config["report_path"].string))
        var settings = OpenAISettingsStore.load(providerID: "openai").voice
        if let model = config["model"].string {
            settings.transcriptionModel = model
        }
        var report: OpenAIJSON = [
            "mode": "live_voice_acceptance", "status": "running", "model": .string(settings.transcriptionModel),
            "speech_model": .string(settings.speechModel), "voice": .string(settings.voice),
            "source_sha256": config["source_sha256"], "synthetic_audio": true,
            "microphone_used": false, "audio_played": false, "competitive_score": false, "checks": [],
        ]
        func save() throws {
            try report.data().write(to: destination, options: .atomic)
        }
        guard let key = ProcessInfo.processInfo.environment["LINEN_OPENAI_LIVE_KEY"] ?? CredentialStore.key(for: ProviderCatalog.openAI), !key.isEmpty else {
            report["status"] = "blocked_missing_credential"
            try save()
            return
        }
        try save()
        let client = OpenAIVoiceClient(endpoint: URL(string: "https://api.openai.com/v1")!, key: key, settings: settings)
        let usage = VoiceLiveUsage()
        var checks: [OpenAIJSON] = []
        do {
            var pcm = Data()
            let started = ContinuousClock.now
            var firstAudio: Int?
            for try await bytes in client.speech("The blue folder contains seven tabs.", onUsage: { await usage.set($0) }) {
                if firstAudio == nil {
                    firstAudio = milliseconds(since: started)
                }
                pcm.append(bytes)
                guard pcm.count <= 24_000 * 2 * 20 else { throw OpenAIVoiceFailure.tooLong }
            }
            guard pcm.count >= 4_800, pcm.count.isMultiple(of: 2) else { throw OpenAIVoiceFailure.invalidAudio }
            checks.append(["name": "streamed_speech", "passed": true,
                           "elapsed_ms": .integer(Int64(milliseconds(since: started))), "first_audio_ms": firstAudio.map { .integer(Int64($0)) } ?? .null,
                           "pcm_bytes": .integer(Int64(pcm.count)), "audio_seconds": .number(Double(pcm.count) / 48_000), "usage": await usage.value,
            ])
            report["checks"] = .array(checks)
            try save()

            let engine = OpenAITranscriberEngine(client: client)
            try engine.prepare()
            let (audio, input) = AsyncStream<CapturedAudio>.makeStream()
            let transcriptionStarted = ContinuousClock.now
            let updates = engine.startSession(input: audio)
            let reader = Task { () throws -> (String, Int?, Int) in
                var final = ""
                var first: Int?
                var count = 0
                for try await update in updates {
                    count += 1
                    if first == nil, !update.text.isEmpty {
                        first = milliseconds(since: transcriptionStarted)
                    }
                    if update.isFinal {
                        final = update.text
                    }
                }
                return (final, first, count)
            }
            do {
                let format = try #require(engine.bestFormat)
                for offset in stride(from: 0, to: pcm.count, by: 9_600) {
                    let length = min(9_600, pcm.count - offset)
                    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(length / 2)))
                    buffer.frameLength = AVAudioFrameCount(length / 2)
                    let samples = try #require(buffer.floatChannelData?[0])
                    for index in 0..<(length / 2) {
                        let bits = UInt16(pcm[offset + index * 2]) | UInt16(pcm[offset + index * 2 + 1]) << 8
                        samples[index] = Float(Int16(bitPattern: bits)) / 32_768
                    }
                    input.yield(CapturedAudio(buffer: buffer))
                    try await Task.sleep(for: .milliseconds(200))
                }
                input.finish()
                try await engine.finishSession()
                let (text, first, count) = try await reader.value
                let normalized = text.lowercased()
                guard normalized.contains("blue"), normalized.contains("folder"), normalized.contains("seven") || normalized.contains("7") else {
                    throw OpenAILiveFailure.invariant
                }
                checks.append(["name": "realtime_transcription", "passed": true,
                               "elapsed_ms": .integer(Int64(milliseconds(since: transcriptionStarted))),
                               "first_transcript_ms": first.map { .integer(Int64($0)) } ?? .null, "transcript_updates": .integer(Int64(count)),
                ])
            } catch {
                input.finish()
                reader.cancel()
                await engine.cancelSession()
                throw error
            }
            report["checks"] = .array(checks)
            report["status"] = "passed"
            try save()
        } catch {
            report["status"] = "failed"
            report["error"] = .string(OpenAILiveRecorder.errorCode(error))
            try save()
            Issue.record("Live voice validation failed; see the sanitized report.")
        }
    }

    private func milliseconds(since started: ContinuousClock.Instant) -> Int {
        let value = started.duration(to: .now).components
        return Int(value.seconds * 1_000 + value.attoseconds / 1_000_000_000_000_000)
    }
}

private actor VoiceLiveUsage {
    var value: OpenAIJSON = .null
    func set(_ value: OpenAIJSON) {
        self.value = value
    }
}
