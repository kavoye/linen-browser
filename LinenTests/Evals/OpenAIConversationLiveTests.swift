// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AVFAudio
import Foundation
import Testing

@testable import Linen

@MainActor
struct OpenAIConversationLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LINEN_OPENAI_LIVE_CONFIG"] != nil))
    func syntheticAudioDelegatesThroughProductionConversationController() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["LINEN_OPENAI_LIVE_CONFIG"])
        let config = try OpenAIJSON.decode(Data(contentsOf: URL(fileURLWithPath: path)))
        guard config["conversation_only"] == true, config["live"] == true else { return }
        let destination = URL(fileURLWithPath: try #require(config["report_path"].string))
        var options = OpenAIVoiceSettings()
        if let model = config["model"].string { options.conversationModel = model }
        var report: OpenAIJSON = [
            "mode": "live_conversation_acceptance", "status": "running", "model": .string(options.conversationModel),
            "source_sha256": config["source_sha256"], "microphone_used": false, "audio_played": false,
            "synthetic_audio": true, "browser_callback": "fixture", "competitive_score": false,
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
        let capture = ConversationCaptureFixture()
        let player = ConversationPlaybackFixture()
        let endpoint = URL(string: "https://api.openai.com/v1")!
        let connect = OpenAIRealtimeConversation.connection(endpoint: endpoint, key: key, model: options.conversationModel)
        let diagnostics = ConversationLiveDiagnostics()
        var usages: [OpenAIJSON] = []
        var requests = 0
        let session = OpenAIRealtimeConversation(settings: options, capture: capture, player: player, connect: {
            ConversationLiveSocket(base: try connect(), diagnostics: diagnostics)
        }) { _ in
            requests += 1
            return "Browser inspection completed: there are seven tabs open."
        }
        session.onUsage = { usages.append($0) }
        defer { session.stop() }
        let timeout = Task {
            try await Task.sleep(for: .seconds(120))
            session.stop()
        }
        defer { timeout.cancel() }
        do {
            let speech = OpenAIVoiceClient(endpoint: endpoint, key: key, settings: options)
            var pcm = Data()
            var speechUsage: OpenAIJSON = .null
            let usageBox = ConversationLiveDiagnostics()
            for try await bytes in speech.speech("Please use the browser tool to count how many tabs I have open.", onUsage: { await usageBox.setSpeechUsage($0) }) {
                pcm.append(bytes)
                guard pcm.count <= 24_000 * 2 * 20 else { throw OpenAIVoiceFailure.tooLong }
            }
            speechUsage = await usageBox.speechUsage
            report["speech_usage"] = speechUsage
            report["synthetic_pcm_bytes"] = .integer(Int64(pcm.count))
            try save()
            session.start()
            try await until { session.phase == .listening || !session.isActive }
            guard session.phase == .listening else { throw OpenAILiveFailure.invariant }
            let started = ContinuousClock.now
            pcm.append(Data(count: 24_000 * 2 * 4))
            let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1))
            for offset in stride(from: 0, to: pcm.count, by: 9_600) {
                guard session.isActive else { throw OpenAILiveFailure.invariant }
                let count = min(9_600, pcm.count - offset) / 2
                let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)))
                buffer.frameLength = AVAudioFrameCount(count)
                for index in 0..<count {
                    let bits = UInt16(pcm[offset + index * 2]) | UInt16(pcm[offset + index * 2 + 1]) << 8
                    buffer.floatChannelData?[0][index] = Float(Int16(bitPattern: bits)) / 32_768
                }
                capture.input?.yield(CapturedAudio(buffer: buffer))
                try await Task.sleep(for: .milliseconds(200))
            }
            try await until { !session.isActive || (session.responseCount >= 2 && player.finishes > 0) }
            guard session.isActive, requests == 1, player.bytes > 0, usages.count >= 2,
                  session.inputTokens > 0, session.outputTokens > 0 else { throw OpenAILiveFailure.invariant }
            let elapsed = started.duration(to: .now).components
            report["elapsed_ms"] = .integer(elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000)
            report["status"] = "passed"
        } catch {
            report["status"] = "failed"
            report["error"] = .string(OpenAILiveRecorder.errorCode(error))
            Issue.record("Conversational voice acceptance failed; see the sanitized report.")
        }
        report["response_usage"] = .array(usages)
        report["browser_dispatch_count"] = .integer(Int64(requests))
        report["output_pcm_bytes"] = .integer(Int64(player.bytes))
        report["response_count"] = .integer(Int64(session.responseCount))
        report["events"] = .array(await diagnostics.types.map(OpenAIJSON.string))
        report["server_error_code"] = .string(await diagnostics.errorCode)
        try save()
    }

    private func until(_ predicate: () -> Bool) async throws {
        for _ in 0..<600 {
            if predicate() {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw OpenAILiveFailure.invariant
    }
}

private actor ConversationLiveDiagnostics {
    var types: [String] = []
    var errorCode = ""
    var speechUsage: OpenAIJSON = .null
    func setSpeechUsage(_ usage: OpenAIJSON) {
        speechUsage = usage
    }
    func record(_ event: OpenAIJSON) {
        if let type = event["type"].string, !types.contains(type), types.count < 80 { types.append(type) }
        if event["type"] == "error", let code = event["error"]["code"].string,
           code.count < 100, code.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) {
            errorCode = code
        }
    }
}

private actor ConversationLiveSocket: OpenAISocketConnection {
    let base: any OpenAISocketConnection
    let diagnostics: ConversationLiveDiagnostics
    init(base: any OpenAISocketConnection, diagnostics: ConversationLiveDiagnostics) {
        self.base = base
        self.diagnostics = diagnostics
    }
    func send(_ event: OpenAIJSON) async throws {
        try await base.send(event)
    }
    func receive() async throws -> OpenAIJSON {
        let event = try await base.receive()
        await diagnostics.record(event)
        return event
    }
    func close() async {
        await base.close()
    }
}
