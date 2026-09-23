// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AVFAudio
import Foundation
import Testing

@testable import Linen

@MainActor
@Suite(.serialized)
struct OpenAIConversationTests {
    @Test func voiceHistoryPairsLateUserTranscriptionWithItsAssistantReply() async throws {
        let fixture = ConversationFixture()
        let database = AppDatabase.temporary()
        let log = ConversationLog(database: database)
        let space = UUID()
        fixture.session.onTranscriptChanged = log.voiceTranscriptWriter(tabID: space, providerID: "openai")
        defer { fixture.session.stop() }
        try await fixture.startResponse()
        await fixture.socket.push(["type": "response.output_audio_transcript.delta", "response_id": "response", "item_id": "answer", "delta": "Three links."])
        try #require(await waitUntil { log.traces.count == 1 })
        await fixture.socket.push(["type": "conversation.item.input_audio_transcription.completed", "item_id": "user", "transcript": "What is on the page?"])
        try #require(await waitUntil { log.traces.first?.prompt == "What is on the page?" })
        #expect(log.traces.count == 1)
        fixture.session.stop()
        log.saveBlocking()
        let reopened = ConversationLog(database: database)
        #expect(reopened.exchanges(forTab: space) == [.init(prompt: "What is on the page?", response: "Three links.")])
    }

    @Test func stoppingDuringMicrophoneStartupDoesNotReviveTheSession() async throws {
        let fixture = ConversationFixture()
        fixture.capture.blocksStart = true
        fixture.session.start()
        try #require(await waitUntil { fixture.capture.starts == 1 })
        fixture.session.stop()
        fixture.capture.finishStarting()
        await Task.yield()
        #expect(fixture.session.phase == .stopped)
        #expect(fixture.session.failure == nil)
        #expect(fixture.capture.stops > 0)
    }

    @Test func basicCaptureSuppressesSpeakerEchoAndAllowsExplicitInterruption() async throws {
        let fixture = ConversationFixture()
        fixture.capture.usesEchoCancellation = false
        fixture.player.blocks = true
        defer { fixture.session.stop() }
        try await fixture.startResponse()
        await fixture.socket.push(fixture.audio())
        try #require(await waitUntil { fixture.player.bytes == 4 })
        try fixture.capture.emit(value: 0.2)
        try #require(await waitUntil { fixture.session.inputFrames > 0 })
        #expect(await fixture.socket.sent.allSatisfy { $0["type"] != "input_audio_buffer.append" })
        fixture.session.interruptReply()
        try #require(await fixture.socket.waitFor("response.cancel"))
        let frames = fixture.session.inputFrames
        try fixture.capture.emit(value: 0.2)
        try #require(await waitUntil { fixture.session.inputFrames > frames })
        #expect(await fixture.socket.sent.allSatisfy { $0["type"] != "input_audio_buffer.append" })
        fixture.date += 1
        try fixture.capture.emit(value: 0.2)
        #expect(await fixture.socket.waitFor("input_audio_buffer.append"))
    }

    @Test func silentAndStalledMicrophonesHaveDistinctFeedback() async throws {
        let fixture = ConversationFixture()
        defer { fixture.session.stop() }
        fixture.session.start()
        try #require(await waitUntil { fixture.session.phase == .listening })
        #expect(fixture.session.statusText == String(localized: "Starting microphone…"))
        fixture.date += 7
        try fixture.capture.emit(value: 0)
        try #require(await waitUntil { fixture.session.inputFrames > 0 })
        fixture.session.checkInputHealth()
        #expect(fixture.session.inputNotice != nil)
        #expect(fixture.session.isActive)
        try fixture.capture.emit(value: 0.1)
        try #require(await waitUntil { fixture.session.inputLevel > 0 })
        #expect(fixture.session.inputNotice == nil)
        fixture.date += 6
        fixture.session.checkInputHealth()
        #expect(fixture.session.phase == .failed)
        #expect(fixture.capture.stops > 0)
    }

    @Test func muteDropsCapturedAudioAndUnmuteResumesSending() async throws {
        let fixture = ConversationFixture()
        defer { fixture.session.stop() }
        fixture.session.start()
        try #require(await waitUntil { fixture.session.phase == .listening })
        try fixture.capture.emit(value: 0.1)
        try #require(await fixture.socket.waitFor("input_audio_buffer.append"))
        fixture.session.toggleMicrophone()
        try #require(await fixture.socket.waitFor("input_audio_buffer.clear"))
        try #require(await waitUntil { !fixture.session.isChangingMicrophone })
        let count = await fixture.socket.sent.filter { $0["type"] == "input_audio_buffer.append" }.count
        let frames = fixture.session.inputFrames
        try fixture.capture.emit(value: 0.5)
        try #require(await waitUntil { fixture.session.inputFrames > frames })
        #expect(fixture.session.inputLevel == 0)
        #expect(await fixture.socket.sent.filter { $0["type"] == "input_audio_buffer.append" }.count == count)
        fixture.session.toggleMicrophone()
        try fixture.capture.emit(value: 0.2)
        #expect(await waitUntil { fixture.session.inputLevel > 0 })
        #expect(!fixture.session.isMicrophoneMuted)
    }

    @Test func committedSpeechBeforeSpeechStoppedStillRequestsAResponse() async throws {
        let fixture = ConversationFixture()
        defer { fixture.session.stop() }
        fixture.session.start()
        try #require(await waitUntil { fixture.session.phase == .listening })
        await fixture.socket.push(["type": "input_audio_buffer.speech_started"])
        await fixture.socket.push(["type": "input_audio_buffer.committed"])
        await fixture.socket.push(["type": "input_audio_buffer.speech_stopped"])
        #expect(await fixture.socket.waitFor("response.create"))
    }

    @Test func userTranscriptAppearsBeforeTranscriptionCompletes() async throws {
        let fixture = ConversationFixture()
        defer { fixture.session.stop() }
        fixture.session.start()
        try #require(await waitUntil { fixture.session.phase == .listening })
        await fixture.socket.push(["type": "conversation.item.input_audio_transcription.delta", "item_id": "user", "delta": "Hello"])
        #expect(await waitUntil { fixture.session.transcript.last?.text == "Hello" })
        await fixture.socket.push(["type": "conversation.item.input_audio_transcription.completed", "item_id": "user", "transcript": "Hello there."])
        #expect(await waitUntil { fixture.session.transcript.last?.text == "Hello there." })
        #expect(fixture.session.transcript.count == 1)
        #expect(fixture.session.transcript.last?.isUser == true)
    }

    @Test func playbackPositionExcludesQueuedAudioLatencyAndStarvationGaps() {
        var timeline = OpenAIPlaybackTimeline()
        let first = timeline.schedule(frames: 24_000, renderedFrame: 0)
        #expect(timeline.playedMilliseconds(renderedFrame: 12_000, latency: 0.1) == 400)
        #expect(timeline.playedMilliseconds(renderedFrame: 1_200, latency: 0.1) == 0)
        timeline.complete(start: first)
        let second = timeline.schedule(frames: 24_000, renderedFrame: 72_000)
        #expect(second == 72_000)
        #expect(timeline.playedMilliseconds(renderedFrame: 74_400, latency: 0.1) == 1_000)
        #expect(timeline.playedMilliseconds(renderedFrame: 76_800, latency: 0.1) == 1_100)
        #expect(timeline.playedMilliseconds(renderedFrame: 0, latency: .nan) == 1_000)
        timeline.complete(start: second)
        #expect(timeline.playedMilliseconds(renderedFrame: 0, latency: 0) == 2_000)
    }

    @Test func openingAndStoppingWithoutStartingDoesNotConnectOrCapture() {
        let fixture = ConversationFixture()
        #expect(fixture.capture.starts == 0)
        #expect(fixture.session.phase == .idle)
        fixture.session.stop()
        #expect(fixture.capture.starts == 0)
    }

    @Test func configurationKeepsExactModelAndManualResponseControl() throws {
        var options = OpenAIVoiceSettings()
        options.conversationModel = "exact-future-model"
        let config = try options.conversationConfiguration()["session"]
        #expect(config["model"] == "exact-future-model")
        #expect(config["audio"]["input"]["turn_detection"]["create_response"] == false)
        #expect(config["audio"]["input"]["turn_detection"]["interrupt_response"] == false)
        #expect(config["max_output_tokens"] == 2_048)
        #expect(config["tools"].array?.first?["name"] == "browser_task")
        let legacy = try JSONDecoder().decode(OpenAIVoiceSettings.self, from: Data("{}".utf8))
        #expect(legacy.conversationVoice == "cedar")
        options.conversationModel = " "
        #expect(throws: OpenAIVoiceFailure.self) { try options.conversationConfiguration() }
    }

    @Test func legacyVoiceServiceChoiceIsIgnored() throws {
        let legacy = Data(#"{"usesOpenAI":false,"voice":"sage"}"#.utf8)
        let options = try JSONDecoder().decode(OpenAIVoiceSettings.self, from: legacy)
        #expect(options.voice == "sage")
        let saved = try JSONEncoder().encode(options)
        let fields = try #require(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        #expect(fields["usesOpenAI"] == nil)
    }

    @Test func streamedAudioAndTranscriptsAreCorrelatedAndUsageIsCountedOnce() async throws {
        let fixture = ConversationFixture()
        defer { fixture.session.stop() }
        try await fixture.startResponse()
        await fixture.socket.push(fixture.audio())
        await fixture.socket.push(["type": "response.output_audio_transcript.delta", "response_id": "response", "item_id": "audio", "delta": "Hello"])
        await fixture.socket.push(["type": "response.output_audio.done", "response_id": "response", "item_id": "audio"])
        await fixture.socket.push(fixture.done())
        await fixture.socket.push(fixture.done())
        #expect(await waitUntil { fixture.session.responseCount == 1 && fixture.player.finishes == 1 })
        #expect(fixture.player.bytes == 4)
        #expect(fixture.session.transcript.last?.text == "Hello")
        #expect(fixture.session.inputTokens == 30)
        #expect(fixture.session.outputTokens == 10)
        #expect(fixture.usage.count == 1)
        #expect(fixture.capture.starts == 1)
    }

    @Test func interruptionStopsBlockedPlaybackAndTruncatesOnlyPlayedAudio() async throws {
        let fixture = ConversationFixture()
        fixture.player.blocks = true
        fixture.player.playedMilliseconds = 125
        defer { fixture.session.stop() }
        try await fixture.startResponse()
        await fixture.socket.push(fixture.audio())
        try #require(await waitUntil { fixture.player.bytes == 4 })
        await fixture.socket.push(["type": "input_audio_buffer.speech_started"])
        try #require(await waitUntil { fixture.player.stops >= 2 })
        #expect(await fixture.socket.waitFor("conversation.item.truncate"))
        let sent = await fixture.socket.sent
        #expect(sent.first { $0["type"] == "conversation.item.truncate" }?["audio_end_ms"] == 125)
        #expect(sent.contains { $0["type"] == "response.cancel" })
        await fixture.socket.push(fixture.audio())
        await fixture.socket.push(fixture.done(status: "cancelled"))
        #expect(await waitUntil { fixture.session.responseCount == 1 })
        #expect(fixture.player.bytes == 4)
        #expect(fixture.session.isActive)
    }

    @Test func interruptionBeforeResponseCreatedCancelsItBeforePlaying() async throws {
        let fixture = ConversationFixture()
        defer { fixture.session.stop() }
        try await fixture.startResponse(created: false)
        await fixture.socket.push(["type": "input_audio_buffer.speech_started"])
        await fixture.socket.push(["type": "response.created", "response": ["id": "response"]])
        #expect(await fixture.socket.waitFor("response.cancel"))
        await fixture.socket.push(fixture.audio())
        await fixture.socket.push(fixture.done(status: "cancelled"))
        #expect(await waitUntil { fixture.session.responseCount == 1 })
        #expect(fixture.player.bytes == 0)
    }

    @Test func functionDeltasNeverExecuteAndCompletedCallsReturnOutput() async throws {
        let fixture = ConversationFixture()
        defer { fixture.session.stop() }
        try await fixture.startResponse()
        await fixture.socket.push(["type": "response.function_call_arguments.done", "name": "browser_task", "arguments": "{}"])
        await fixture.socket.push(fixture.done(output: [fixture.call()]))
        #expect(await fixture.socket.waitFor("conversation.item.create"))
        #expect(fixture.requests == ["Inspect the current page"])
        let sent = await fixture.socket.sent
        #expect(sent.first { $0["type"] == "conversation.item.create" }?["item"]["call_id"] == "call")
    }

    @Test func cancelledFunctionNeverDispatches() async throws {
        let fixture = ConversationFixture()
        defer { fixture.session.stop() }
        try await fixture.startResponse()
        await fixture.socket.push(fixture.done(status: "cancelled", output: [fixture.call()]))
        #expect(await waitUntil { fixture.session.responseCount == 1 })
        #expect(fixture.requests.isEmpty)
    }

    @Test func interruptionDuringBrowserWorkCancelsAndReturnsAnExplicitResult() async throws {
        let fixture = ConversationFixture()
        fixture.blocksBrowser = true
        defer { fixture.session.stop() }
        try await fixture.startResponse()
        await fixture.socket.push(fixture.done(output: [fixture.call()]))
        try #require(await waitUntil { fixture.requests.count == 1 })
        await fixture.socket.push(["type": "input_audio_buffer.speech_started"])
        #expect(await fixture.socket.waitFor("conversation.item.create"))
        let sent = await fixture.socket.sent
        #expect(sent.first { $0["type"] == "conversation.item.create" }?["item"]["output"].string?.contains("Cancelled") == true)
        #expect(fixture.browserCancelled)
        #expect(fixture.session.isActive)
    }

    @Test func malformedAudioAndUnsupportedActionsStopTheSession() async throws {
        for invalid in [OpenAIJSON.object([:]), .null] {
            let fixture = ConversationFixture()
            try await fixture.startResponse()
            if invalid == .null {
                await fixture.socket.push(fixture.done(output: [["type": "computer_call"]]))
            } else {
                var event = fixture.audio()
                event["delta"] = "invalid base64!"
                await fixture.socket.push(event)
            }
            #expect(await waitUntil { fixture.session.phase == .failed })
            #expect(fixture.capture.stops > 0)
            #expect(fixture.requests.isEmpty)
        }
    }

    @Test func stoppingDuringBrowserWorkNeverPublishesItsLateResult() async throws {
        let fixture = ConversationFixture()
        fixture.blocksBrowser = true
        try await fixture.startResponse()
        await fixture.socket.push(fixture.done(output: [fixture.call()]))
        try #require(await waitUntil { fixture.requests.count == 1 })
        fixture.session.stop()
        #expect(await waitUntil { fixture.browserCancelled })
        #expect(await fixture.socket.closed)
        #expect(await fixture.socket.sent.allSatisfy { $0["type"] != "conversation.item.create" })
    }
}

@MainActor
private final class ConversationFixture {
    let socket = ConversationSocketFixture()
    let capture = ConversationCaptureFixture()
    let player = ConversationPlaybackFixture()
    var requests: [String] = []
    var usage: [OpenAIJSON] = []
    var blocksBrowser = false
    var browserCancelled = false
    var date = Date()
    var session: OpenAIRealtimeConversation!

    init() {
        let socket = socket
        let session = OpenAIRealtimeConversation(settings: .init(), capture: capture, player: player, now: { [weak self] in self?.date ?? Date() }, connect: { socket }) { [weak self] request in
            guard let self else { throw CancellationError() }
            requests.append(request)
            if blocksBrowser {
                let (pending, continuation) = AsyncStream<Void>.makeStream()
                defer { continuation.finish() }
                for await _ in pending {}
                browserCancelled = Task.isCancelled
                try Task.checkCancellation()
            }
            return "The page contains three links."
        }
        session.onUsage = { [weak self] in self?.usage.append($0) }
        self.session = session
    }

    func startResponse(created: Bool = true) async throws {
        session.start()
        try #require(await waitForObservation { self.session.phase == .listening || self.session.phase == .failed })
        try #require(session.phase == .listening)
        await socket.push(["type": "input_audio_buffer.committed", "item_id": "user"])
        try #require(await socket.waitFor("response.create"))
        if created { await socket.push(["type": "response.created", "response": ["id": "response"]]) }
    }

    func audio() -> OpenAIJSON {
        ["type": "response.output_audio.delta", "response_id": "response", "item_id": "audio", "content_index": 0, "delta": "AAABAA=="]
    }
    func done(status: String = "completed", output: [OpenAIJSON] = []) -> OpenAIJSON {
        ["type": "response.done", "response": ["id": "response", "status": .string(status), "output": .array(output),
                                                 "usage": ["input_tokens": 30, "output_tokens": 10], ], ]
    }
    func call() -> OpenAIJSON {
        ["type": "function_call", "name": "browser_task", "call_id": "call", "arguments": "{\"request\":\"Inspect the current page\"}"]
    }
}

actor ConversationSocketFixture: OpenAISocketConnection {
    var sent: [OpenAIJSON] = []
    var closed = false
    private var queue: [OpenAIJSON] = []
    private var reader: CheckedContinuation<OpenAIJSON, any Error>?
    func send(_ event: OpenAIJSON) {
        sent.append(event)
        if event["type"] == "session.update" {
            push(["type": "session.updated"])
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
    func push(_ event: OpenAIJSON) {
        if let reader {
            self.reader = nil
            reader.resume(returning: event)
        } else { queue.append(event) }
    }
    func waitFor(_ type: String) async -> Bool {
        for _ in 0..<100 {
            if sent.contains(where: { $0["type"].string == type }) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

@MainActor
final class ConversationCaptureFixture: AudioInputCapturing {
    var usesEchoCancellation = true
    var blocksStart = false
    private var starting: CheckedContinuation<Void, Never>?
    var starts = 0
    var stops = 0
    var input: AsyncStream<CapturedAudio>.Continuation?
    func start(targetFormat: AVAudioFormat) async throws -> AsyncStream<CapturedAudio> {
        starts += 1
        if blocksStart {
            await withCheckedContinuation { starting = $0 }
        }
        try Task.checkCancellation()
        return AsyncStream { input = $0 }
    }
    func finishStarting() {
        starting?.resume()
        starting = nil
    }
    func emit(value: Float) throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2_400))
        buffer.frameLength = 2_400
        let samples = try #require(buffer.floatChannelData?[0])
        samples.initialize(repeating: value, count: 2_400)
        input?.yield(CapturedAudio(buffer: buffer))
    }
    func stop() {
        stops += 1
        input?.finish()
        input = nil
    }
}

@MainActor
final class ConversationPlaybackFixture: ConversationAudioPlaying {
    var playedMilliseconds = 0
    var bytes = 0
    var finishes = 0
    var stops = 0
    var blocks = false
    private var continuation: CheckedContinuation<Void, any Error>?
    func append(_ pcm: Data) async throws {
        bytes += pcm.count
        if blocks {
            try await withCheckedThrowingContinuation { continuation = $0 }
        }
    }
    func finish() {
        finishes += 1
    }
    func stop() {
        stops += 1
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}
