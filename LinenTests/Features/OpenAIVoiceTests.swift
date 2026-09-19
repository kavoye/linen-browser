// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AVFAudio
import Foundation
import Testing

@testable import Linen

@MainActor
struct OpenAIVoiceTests {
    @Test func transcriptionCommitsOnlyAfterCaptureFinishes() async throws {
        let socket = VoiceSocketFixture()
        let client = OpenAIVoiceClient(transport: VoiceSpeechFixture(), settings: .init(), makeSocket: { socket })
        let engine = OpenAITranscriberEngine(client: client)
        try engine.prepare()
        let (audio, input) = AsyncStream<CapturedAudio>.makeStream()
        let updates = engine.startSession(input: audio)
        let reader = Task { () throws -> [TranscriptUpdate] in
            var result: [TranscriptUpdate] = []
            for try await update in updates {
                result.append(update)
            }
            return result
        }
        input.yield(try sample())
        #expect(await waitUntil { await socket.appendCount == 1 })
        #expect(await socket.commitCount == 0)
        input.finish()
        try await engine.finishSession()
        let result = try await reader.value
        #expect(result.last == TranscriptUpdate(text: "Blue folder", isFinal: true))
        #expect(result.contains { !$0.isFinal && $0.text == "Blue" })
        #expect(await socket.commitCount == 1)
        #expect(await socket.closed)
    }

    @Test func cancellingTranscriptionClosesSocketWithoutCommitting() async throws {
        let socket = VoiceSocketFixture()
        let engine = OpenAITranscriberEngine(client: .init(transport: VoiceSpeechFixture(), settings: .init(), makeSocket: { socket }))
        try engine.prepare()
        let (audio, input) = AsyncStream<CapturedAudio>.makeStream()
        let updates = engine.startSession(input: audio)
        let reader = Task { for try await _ in updates {} }
        input.yield(try sample())
        #expect(await waitUntil { await socket.appendCount == 1 })
        await engine.cancelSession()
        input.finish()
        _ = try? await reader.value
        #expect(await socket.commitCount == 0)
        #expect(await socket.closed)
    }

    @Test func finalTranscriptIsMatchedToTheCommittedItem() throws {
        var assembler = OpenAITranscriptAssembler()
        #expect(try assembler.receive(["type": "conversation.item.input_audio_transcription.completed", "item_id": "old", "transcript": "stale"]) == nil)
        #expect(try assembler.receive(["type": "input_audio_buffer.committed", "item_id": "new"]) == nil)
        let final = try assembler.receive(["type": "conversation.item.input_audio_transcription.completed", "item_id": "new", "transcript": "correct"])
        #expect(final == TranscriptUpdate(text: "correct", isFinal: true))
        #expect(throws: OpenAIVoiceFailure.transcription) {
            try assembler.receive(["type": "conversation.item.input_audio_transcription.failed"])
        }
    }

    @Test func pcmEncodingClampsAndUsesLittleEndian() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3))
        buffer.frameLength = 3
        let samples = try #require(buffer.floatChannelData?[0])
        samples[0] = -2
        samples[1] = 0
        samples[2] = 2
        #expect(try OpenAIPCM.encode(buffer) == Data([1, 128, 0, 0, 255, 127]))
        samples[1] = .nan
        #expect(throws: OpenAIVoiceFailure.invalidAudio) { try OpenAIPCM.encode(buffer) }
    }

    @Test func speechStreamsPCMAndDoesNotInheritChatSettings() async throws {
        let transport = VoiceSpeechFixture()
        let client = OpenAIVoiceClient(transport: transport, settings: .init(), makeSocket: { VoiceSocketFixture() })
        let reader = Task { () throws -> Data in
            var data = Data()
            for try await piece in client.speech("Hello") {
                data.append(piece)
            }
            return data
        }
        #expect(await waitUntil { transport.requests.count == 1 })
        transport.complete(index: 0)
        #expect(try await reader.value == Data([0, 0, 1, 0]))
        let request = try #require(transport.requests.first)
        let body = try OpenAIJSON.decode(try #require(request.body))
        #expect(request.path == ["audio", "speech"])
        #expect(body["model"] == "gpt-4o-mini-tts")
        #expect(body["voice"] == "cedar")
        #expect(body["response_format"] == "pcm")
        #expect(body["stream_format"] == "sse")
        #expect(body["tools"] == .null)
    }

    @Test func interruptedSpeechNeverReportsSuccessfulCompletion() async throws {
        let transport = VoiceSpeechFixture()
        let client = OpenAIVoiceClient(transport: transport, settings: .init(), makeSocket: { VoiceSocketFixture() })
        let reader = Task { for try await _ in client.speech("Hello") {} }
        #expect(await waitUntil { transport.requests.count == 1 })
        transport.complete(index: 0, terminal: false)
        await #expect(throws: OpenAIVoiceFailure.interrupted) { try await reader.value }
    }

    @Test func stoppingSpeechRejectsLateAudioAndAllowsANewUtterance() async throws {
        let transport = VoiceSpeechFixture()
        let player = VoicePlaybackFixture()
        let output = OpenAISpeechOutput(client: .init(transport: transport, settings: .init(), makeSocket: { VoiceSocketFixture() }), playback: player)
        output.speak("Old")
        #expect(await waitUntil { transport.requests.count == 1 })
        output.stopSpeaking()
        transport.complete(index: 0)
        output.speak("New")
        #expect(await waitUntil { transport.requests.count == 2 })
        transport.complete(index: 1)
        #expect(await waitUntil { player.finishes == 1 })
        #expect(player.audio == Data([0, 0, 1, 0]))
        output.stopSpeaking()
    }

    @Test func explicitReadAloudCanFinishWhenTheDefaultIsMuted() async throws {
        let transport = VoiceSpeechFixture()
        let player = VoicePlaybackFixture()
        let output = OpenAISpeechOutput(client: .init(transport: transport, settings: .init(), makeSocket: { VoiceSocketFixture() }), playback: player)
        output.isMuted = true
        output.speak("Muted")
        #expect(transport.requests.isEmpty)
        output.isMuted = false
        output.speak("Explicit read aloud")
        output.isMuted = true
        #expect(await waitUntil { transport.requests.count == 1 })
        transport.complete(index: 0)
        #expect(await waitUntil { player.finishes == 1 })
        output.stopSpeaking()
    }

    @Test func providerChangesStopOldOutputAndIgnoreItsCallbacks() {
        let old = VoiceOutputFixture()
        let next = VoiceOutputFixture()
        let router = ProviderSpeechOutput(output: old)
        router.isMuted = true
        var changes: [Bool] = []
        router.onSpeakingChange = { changes.append($0) }
        let stale = old.onSpeakingChange
        router.use(next)
        stale?(true)
        #expect(old.stops >= 1)
        #expect(next.isMuted)
        #expect(changes == [false])
    }

    @Test func settingsAndTextChunksPreserveExistingData() throws {
        let settings = try JSONDecoder().decode(OpenAIResponseSettings.self, from: Data("{\"verbosity\":\"high\"}".utf8))
        #expect(settings.verbosity == "high")
        #expect(settings.voice.transcriptionModel == "gpt-live-transcribe")
        let text = String(repeating: "Hello café 🌱. ", count: 300)
        let chunks = OpenAISpeechOutput.chunks(text)
        #expect(chunks.joined() == text)
        #expect(chunks.allSatisfy { $0.unicodeScalars.count <= 1_000 })
    }

    private func sample() throws -> CapturedAudio {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800))
        buffer.frameLength = 4_800
        buffer.floatChannelData?[0].initialize(repeating: 0, count: 4_800)
        return CapturedAudio(buffer: buffer)
    }
}

private actor VoiceSocketFixture: OpenAISocketConnection {
    var appendCount = 0
    var commitCount = 0
    var closed = false
    private var queue: [OpenAIJSON] = []
    private var reader: CheckedContinuation<OpenAIJSON, any Error>?

    func send(_ event: OpenAIJSON) {
        switch event["type"].string {
        case "session.update":
            push(["type": "session.updated"])
        case "input_audio_buffer.append":
            appendCount += 1
            push(["type": "conversation.item.input_audio_transcription.delta", "item_id": "turn", "delta": "Blue"])
        case "input_audio_buffer.commit":
            commitCount += 1
            push(["type": "input_audio_buffer.committed", "item_id": "turn"])
            push(["type": "conversation.item.input_audio_transcription.completed", "item_id": "turn", "transcript": "Blue folder"])
        default:
            break
        }
    }

    func receive() async throws -> OpenAIJSON {
        if !queue.isEmpty {
            return queue.removeFirst()
        }
        guard !closed else { throw CancellationError() }
        return try await withCheckedThrowingContinuation { reader = $0 }
    }

    func close() {
        closed = true
        reader?.resume(throwing: CancellationError())
        reader = nil
    }

    private func push(_ event: OpenAIJSON) {
        if let reader {
            self.reader = nil
            reader.resume(returning: event)
        } else { queue.append(event) }
    }
}

nonisolated private final class VoiceSpeechFixture: OpenAITransport, @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [OpenAIRequest] = []
    private var streams: [AsyncThrowingStream<OpenAIEvent, any Error>.Continuation] = []
    var requests: [OpenAIRequest] {
        lock.withLock { seen }
    }

    func send(_ request: OpenAIRequest) async throws -> OpenAIHTTPResult {
        throw OpenAIVoiceFailure.configuration
    }

    func events(_ request: OpenAIRequest) -> AsyncThrowingStream<OpenAIEvent, any Error> {
        AsyncThrowingStream { continuation in
            lock.withLock {
                seen.append(request)
                streams.append(continuation)
            }
        }
    }

    func complete(index: Int, terminal: Bool = true) {
        let stream = lock.withLock { streams[index] }
        stream.yield(.init(type: "speech.audio.delta", payload: ["audio": "AAABAA=="], id: nil))
        if terminal {
            stream.yield(.init(type: "speech.audio.done", payload: [:], id: nil))
        }
        stream.finish()
    }
}

@MainActor
private final class VoicePlaybackFixture: StreamingSpeechPlaying {
    var audio = Data()
    var finishes = 0
    func append(_ pcm: Data) {
        audio.append(pcm)
    }
    func finish() {
        finishes += 1
    }
    func stop() {}
}

@MainActor
private final class VoiceOutputFixture: SpeechOutput {
    var isMuted = false
    var onSpeakingChange: ((Bool) -> Void)?
    var stops = 0
    func speak(_ text: String) {}
    func stopSpeaking() {
        stops += 1
    }
}
