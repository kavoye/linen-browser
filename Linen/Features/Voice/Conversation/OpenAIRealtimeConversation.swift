// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AVFAudio
import Foundation
import Observation

@MainActor
@Observable
final class OpenAIRealtimeConversation {
    enum Phase { case idle, connecting, listening, thinking, speaking, working, stopped, failed }
    struct Transcript: Identifiable {
        let id: String
        let turnID: UUID
        let isUser: Bool
        var text: String
    }

    private(set) var phase: Phase = .idle
    private(set) var transcript: [Transcript] = []
    private(set) var inputTokens = 0
    private(set) var outputTokens = 0
    private(set) var responseCount = 0
    private(set) var failure: String?
    private(set) var inputLevel = 0.0
    private(set) var inputFrames = 0
    private(set) var inputNotice: String?
    private(set) var isMicrophoneMuted = false
    private(set) var isChangingMicrophone = false
    private(set) var usesEchoCancellation = true
    var isActive: Bool {
        ![.idle, .stopped, .failed].contains(phase)
    }

    @ObservationIgnored private let settings: OpenAIVoiceSettings
    @ObservationIgnored private let connect: @Sendable () throws -> any OpenAISocketConnection
    @ObservationIgnored private let capture: any AudioInputCapturing
    @ObservationIgnored private let player: any ConversationAudioPlaying
    @ObservationIgnored private let browserTask: @MainActor (String) async throws -> String
    @ObservationIgnored var onTranscriptChanged: ((UUID, String, String) -> Void)?
    @ObservationIgnored private var itemTurns: [String: UUID] = [:]
    @ObservationIgnored private var pendingTranscriptTurn: UUID?
    @ObservationIgnored private var requestedTranscriptTurn: UUID?
    @ObservationIgnored private var responseTurns: [String: UUID] = [:]
    @ObservationIgnored var onUsage: ((OpenAIJSON) -> Void)?
    @ObservationIgnored private var socket: (any OpenAISocketConnection)?
    @ObservationIgnored private var receiver: Task<Void, Never>?
    @ObservationIgnored private var microphone: Task<Void, Never>?
    @ObservationIgnored private var playback: Task<Void, Never>?
    @ObservationIgnored private var browserWork: Task<Void, Never>?
    @ObservationIgnored private var deadline: Task<Void, Never>?
    @ObservationIgnored private var inputMonitor: Task<Void, Never>?
    @ObservationIgnored private var muteTransition: Task<Void, Never>?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var inputStartedAt: Date?
    @ObservationIgnored private var lastInputAt: Date?
    @ObservationIgnored private var hasInputSignal = false
    @ObservationIgnored private var inputResumesAt = Date.distantPast
    @ObservationIgnored private var ready = false
    @ObservationIgnored private var userSpeaking = false
    @ObservationIgnored private var pendingInput = false
    @ObservationIgnored private var requestedResponse = false
    @ObservationIgnored private var interrupted = false
    @ObservationIgnored private var responseID: String?
    @ObservationIgnored private var cancelSent = false
    @ObservationIgnored private var cancellationEvents: Set<String> = []
    @ObservationIgnored private var completedResponses: Set<String> = []
    @ObservationIgnored private var callIDs: Set<String> = []
    @ObservationIgnored private var audioItem: String?
    @ObservationIgnored private var audioIndex = 0
    @ObservationIgnored private var audioResponse: String?
    @ObservationIgnored private var queuedBytes = 0
    @ObservationIgnored private var audioContinuation: AsyncStream<Data>.Continuation?

    init(settings: OpenAIVoiceSettings, capture: any AudioInputCapturing = AudioCaptureService(conversational: true),
         player: any ConversationAudioPlaying = OpenAIPCMPlayback(),
         now: @escaping () -> Date = Date.init,
         connect: @escaping @Sendable () throws -> any OpenAISocketConnection,
         browserTask: @escaping @MainActor (String) async throws -> String) {
        self.settings = settings
        self.capture = capture
        self.player = player
        self.connect = connect
        self.browserTask = browserTask
        self.now = now
    }

    static func connection(endpoint: URL, key: String, model: String) -> @Sendable () throws -> any OpenAISocketConnection {
        {
            guard !key.isEmpty else { throw OpenAIVoiceFailure.configuration }
            let http = OpenAIHTTPTransport(baseURL: endpoint, apiKey: key)
            return try OpenAISocket(request: http.urlRequest(.init(path: ["realtime"], method: "GET", query: ["model": model])))
        }
    }

    func start() {
        guard phase == .idle else { return }
        phase = .connecting
        receiver = Task { [weak self] in
            guard let self else { return }
            do {
                let configuration = try settings.conversationConfiguration()
                let socket = try connect()
                self.socket = socket
                deadline = Task { [weak self] in
                    do {
                        try await Task.sleep(for: .seconds(15))
                        guard let self, isActive else { return }
                        if !ready {
                            fail(); return
                        }
                        try await Task.sleep(for: .seconds(885))
                        if isActive {
                            fail(message: String(localized: "Voice conversation reached its 15-minute limit. Start a new conversation to continue."))
                        }
                    } catch {   }
                }
                try await socket.send(configuration)
                while isActive {
                    let event = try await socket.receive()
                    guard isActive else { return }
                    try await handle(event)
                }
            } catch {
                if isActive {
                    fail()
                }
            }
        }
    }

    func stop() {
        guard phase != .stopped && phase != .failed else { return }
        phase = .stopped
        receiver?.cancel()
        microphone?.cancel()
        browserWork?.cancel()
        deadline?.cancel()
        inputMonitor?.cancel()
        muteTransition?.cancel()
        inputLevel = 0
        isChangingMicrophone = false
        capture.stop()
        stopPlayback()
        if let socket {
            Task { await socket.close() }
        }
        socket = nil
    }

    private func fail(message: String = String(localized: "Voice conversation stopped. Check your OpenAI voice settings and connection before starting again.")) {
        stop()
        failure = message
        phase = .failed
    }

    private func send(_ event: OpenAIJSON) async throws {
        try Task.checkCancellation()
        guard isActive, let socket else { throw CancellationError() }
        try await socket.send(event)
        guard isActive else { throw CancellationError() }
    }

    private func beginCapture() async throws {
        guard !ready, let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1) else { return }
        let stream: AsyncStream<CapturedAudio>
        do {
            stream = try await capture.start(targetFormat: format)
            guard isActive, !Task.isCancelled else { return }
            capture.setMuted(isMicrophoneMuted)
        } catch {
            guard isActive, !Task.isCancelled else { return }
            fail(message: String(localized: "Couldn’t start the microphone. Check your microphone input and try again."))
            return
        }
        usesEchoCancellation = capture.usesEchoCancellation
        ready = true
        phase = .listening
        inputStartedAt = now()
        lastInputAt = now()
        inputMonitor = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                self?.checkInputHealth()
            }
        }
        microphone = Task { [weak self] in
            guard let self else { return }
            do {
                for await sample in stream {
                    try Task.checkCancellation()
                    lastInputAt = now()
                    inputFrames += Int(sample.buffer.frameLength)
                    guard !isMicrophoneMuted else { continue }
                    let rms = AudioSampleConverter.level(of: sample.buffer) ?? 0
                    guard rms.isFinite else { throw OpenAIVoiceFailure.invalidAudio }
                    inputLevel = min(1, pow(max(0, rms) * 8, 0.6))
                    if rms > 0.00001 {
                        hasInputSignal = true
                        inputNotice = nil
                    }
                    if !usesEchoCancellation && (audioItem != nil || now() < inputResumesAt) {
                        inputLevel = 0
                        continue
                    }
                    let pcm = try OpenAIPCM.encode(sample.buffer)
                    try await send(["type": "input_audio_buffer.append", "audio": .string(pcm.base64EncodedString())])
                }
                if isActive {
                    fail()
                }
            } catch {
                if isActive && !Task.isCancelled {
                    fail()
                }
            }
        }
    }

    private func handle(_ event: OpenAIJSON) async throws {
        switch event["type"].string {
        case "session.updated":
            try await beginCapture()
        case "input_audio_buffer.speech_started":
            userSpeaking = true
            try await interrupt()
        case "input_audio_buffer.speech_stopped":
            userSpeaking = false
            try await requestResponseIfReady()
        case "input_audio_buffer.committed":
            if let item = event["item_id"].string {
                let turn = itemTurns[item] ?? UUID()
                itemTurns[item] = turn
                pendingTranscriptTurn = turn
            }
            pendingInput = true
            try await requestResponseIfReady()
        case "conversation.item.input_audio_transcription.completed":
            updateTranscript(event["item_id"].string, text: event["transcript"].string, isUser: true)
        case "conversation.item.input_audio_transcription.delta":
            appendTranscript(event, isUser: true)
        case "conversation.item.input_audio_transcription.failed":
            throw OpenAIVoiceFailure.interrupted
        case "error":
            try handleServerError(event)
        case "response.created":
            try await responseCreated(event)
        case "response.output_audio.delta":
            guard accepts(event) else { return }
            try enqueueAudio(event)
        case "response.output_audio.done":
            guard accepts(event), event["item_id"].string == audioItem else { return }
            audioContinuation?.finish()
        case "response.output_audio_transcript.delta":
            guard accepts(event) else { return }
            appendTranscript(event, isUser: false)
        case "response.output_audio_transcript.done":
            guard accepts(event) else { return }
            assignAssistantTurn(event, isUser: false)
            updateTranscript(event["item_id"].string, text: event["transcript"].string, isUser: false)
        case "response.done":
            try await completeResponse(event["response"])
        default:
            break
        }
    }

    private func responseCreated(_ event: OpenAIJSON) async throws {
        guard requestedResponse, responseID == nil, let id = event["response"]["id"].string else { throw OpenAIVoiceFailure.interrupted }
        responseID = id
        responseTurns[id] = requestedTranscriptTurn ?? UUID()
        if interrupted {
            try await cancelResponse(id)
        }
    }

    func interruptReply() {
        guard isActive else { return }
        Task { [weak self] in
            guard let self else { return }
            do { try await interrupt() } catch {
                if isActive {
                    fail()
                }
            }
        }
    }

    private func appendTranscript(_ event: OpenAIJSON, isUser: Bool) {
        guard let id = event["item_id"].string, let delta = event["delta"].string else { return }
        assignAssistantTurn(event, isUser: isUser)
        let text = (transcript.first { $0.id == id }?.text ?? "") + delta
        updateTranscript(id, text: text, isUser: isUser)
    }

    var statusText: String {
        if isMicrophoneMuted && isActive {
            return String(localized: "Microphone muted")
        }
        switch phase {
        case .idle, .stopped:
            return String(localized: "Voice conversation ended")
        case .connecting:
            return String(localized: "Connecting…")
        case .listening:
            if inputFrames == 0 {
                return String(localized: "Starting microphone…")
            }
            return inputNotice == nil ? String(localized: "Listening…") : String(localized: "Microphone is silent")
        case .thinking:
            return String(localized: "Thinking…")
        case .speaking:
            return String(localized: "Speaking…")
        case .working:
            return String(localized: "Working in the browser…")
        case .failed:
            return String(localized: "Voice connection stopped")
        }
    }

    func checkInputHealth() {
        guard isActive, ready, !isMicrophoneMuted, let started = inputStartedAt, let last = lastInputAt else { return }
        if now().timeIntervalSince(last) >= 5 {
            fail(message: String(localized: "No audio is arriving from your microphone. Check the input in Sound settings, then try again."))
        } else if !hasInputSignal && now().timeIntervalSince(started) >= 6 {
            inputNotice = String(localized: "No microphone signal detected. Check your input volume and microphone mode in macOS.")
        }
    }

    func toggleMicrophone() {
        guard isActive, ready, !isChangingMicrophone else { return }
        isMicrophoneMuted.toggle()
        capture.setMuted(isMicrophoneMuted)
        inputLevel = 0
        inputNotice = nil
        inputStartedAt = now()
        lastInputAt = now()
        guard isMicrophoneMuted else { return }
        isChangingMicrophone = true
        muteTransition = Task { [weak self] in
            guard let self else { return }
            defer { isChangingMicrophone = false }
            do {
                try await send(["type": "input_audio_buffer.clear"])
                userSpeaking = false
            } catch {
                if isActive && !Task.isCancelled {
                    fail()
                }
            }
        }
    }

    private func handleServerError(_ event: OpenAIJSON) throws {
        guard event["error"]["code"] == "response_cancel_not_active",
              let id = event["error"]["event_id"].string, cancellationEvents.remove(id) != nil else {
            throw OpenAIVoiceFailure.interrupted
        }
    }

    private func accepts(_ event: OpenAIJSON) -> Bool {
        !interrupted && responseID != nil && event["response_id"].string == responseID
    }

    private func assignAssistantTurn(_ event: OpenAIJSON, isUser: Bool) {
        guard !isUser, let item = event["item_id"].string, let response = event["response_id"].string,
              let turn = responseTurns[response] else { return }
        itemTurns[item] = turn
    }

    private func updateTranscript(_ id: String?, text: String?, isUser: Bool) {
        guard let id, let text else { return }
        let bounded = String(text.prefix(12_000))
        let turn = itemTurns[id] ?? UUID()
        itemTurns[id] = turn
        if let index = transcript.firstIndex(where: { $0.id == id }) {
            transcript[index].text = bounded
        } else {
            transcript.append(.init(id: id, turnID: turn, isUser: isUser, text: bounded))
            if transcript.count > 120 {
                transcript.removeFirst()
            }
        }
        let lines = transcript.filter { $0.turnID == turn }
        onTranscriptChanged?(turn, lines.filter(\.isUser).map(\.text).joined(separator: "\n\n"),
                             lines.filter { !$0.isUser }.map(\.text).joined(separator: "\n\n"))
    }

    private func requestResponseIfReady() async throws {
        guard isActive, ready, pendingInput, !userSpeaking, !requestedResponse, browserWork == nil, audioItem == nil else { return }
        guard responseCount < 60 else { throw OpenAIVoiceFailure.tooLong }
        pendingInput = false
        requestedTranscriptTurn = pendingTranscriptTurn ?? requestedTranscriptTurn
        requestedResponse = true
        cancelSent = false
        interrupted = false
        phase = .thinking
        try await send(["type": "response.create"])
    }

    private func interrupt() async throws {
        interrupted = true
        let cancellingResponse = responseID
        let item = audioItem
        let index = audioIndex
        let played = player.playedMilliseconds
        stopPlayback()
        browserWork?.cancel()
        phase = .listening
        if let id = cancellingResponse {
            try await cancelResponse(id)
        }
        if let item {
            try await send(["type": "conversation.item.truncate", "item_id": .string(item),
                            "content_index": .integer(Int64(index)), "audio_end_ms": .integer(Int64(played)), ])
        }
    }

    private func cancelResponse(_ id: String) async throws {
        guard !cancelSent else { return }
        cancelSent = true
        let eventID = UUID().uuidString
        cancellationEvents.insert(eventID)
        try await send(["type": "response.cancel", "response_id": .string(id), "event_id": .string(eventID)])
    }

    private func enqueueAudio(_ event: OpenAIJSON) throws {
        guard let item = event["item_id"].string, let index = event["content_index"].int,
              let encoded = event["delta"].string, encoded.count <= 2_000_000,
              let bytes = Data(base64Encoded: encoded), !bytes.isEmpty else { throw OpenAIVoiceFailure.invalidAudio }
        if audioItem == nil {
            player.stop()
            audioItem = item
            audioIndex = index
            audioResponse = responseID
            let (stream, continuation) = AsyncStream.makeStream(of: Data.self)
            audioContinuation = continuation
            playback = Task { [weak self] in
                guard let self else { return }
                do {
                    for await bytes in stream {
                        try Task.checkCancellation()
                        queuedBytes -= bytes.count
                        try await player.append(bytes)
                    }
                    try Task.checkCancellation()
                    try await player.finish()
                    guard isActive, audioItem == item else { return }
                    inputResumesAt = now().addingTimeInterval(0.35)
                    audioItem = nil
                    audioResponse = nil
                    if !requestedResponse && browserWork == nil {
                        phase = .listening
                    }
                    try await requestResponseIfReady()
                } catch {
                    if !Task.isCancelled && isActive {
                        fail()
                    }
                }
            }
        }
        guard audioItem == item, audioIndex == index, audioResponse == responseID,
              queuedBytes + bytes.count <= 24_000 * 2 * 30 else { throw OpenAIVoiceFailure.invalidAudio }
        queuedBytes += bytes.count
        phase = .speaking
        audioContinuation?.yield(bytes)
    }

    private func stopPlayback() {
        if audioItem != nil {
            inputResumesAt = now().addingTimeInterval(0.35)
        }
        playback?.cancel()
        playback = nil
        audioContinuation?.finish()
        audioContinuation = nil
        audioItem = nil
        audioResponse = nil
        queuedBytes = 0
        player.stop()
    }

    private func completeResponse(_ response: OpenAIJSON) async throws {
        guard let id = response["id"].string, !completedResponses.contains(id) else { return }
        guard id == responseID else { throw OpenAIVoiceFailure.interrupted }
        completedResponses.insert(id)
        responseCount += 1
        let usage = response["usage"]
        inputTokens += max(0, usage["input_tokens"].int ?? 0)
        outputTokens += max(0, usage["output_tokens"].int ?? 0)
        onUsage?(usage)
        responseID = nil
        requestedResponse = false
        let wasInterrupted = interrupted
        interrupted = false
        if wasInterrupted || response["status"] == "cancelled" {
            stopPlayback()
            for call in response["output"].array ?? [] where call["type"] == "function_call" {
                guard let callID = call["call_id"].string else { throw OpenAIVoiceFailure.configuration }
                try await send(["type": "conversation.item.create", "item": ["type": "function_call_output",
                    "call_id": .string(callID), "output": "Cancelled before dispatch. No browser action was started.", ], ])
            }
            try await requestResponseIfReady()
            return
        }
        guard response["status"] == "completed", let output = response["output"].array else { throw OpenAIVoiceFailure.interrupted }
        let calls = output.filter { $0["type"] == "function_call" }
        guard output.allSatisfy({ ["message", "function_call"].contains($0["type"].string ?? "") }), calls.count <= 1 else {
            throw OpenAIVoiceFailure.configuration
        }
        if let call = calls.first {
            try dispatch(call)
        }
        if audioItem == nil && browserWork == nil {
            phase = .listening
        }
        try await requestResponseIfReady()
    }

    private func dispatch(_ call: OpenAIJSON) throws {
        guard browserWork == nil, call["name"] == "browser_task", let id = call["call_id"].string,
              callIDs.insert(id).inserted, let arguments = call["arguments"].string, arguments.utf8.count <= 16_000,
              let fields = try? OpenAIJSON.decode(Data(arguments.utf8)), fields.object?.count == 1,
              let request = fields["request"].string, !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAIVoiceFailure.configuration
        }
        phase = .working
        browserWork = Task { [weak self] in
            guard let self else { return }
            let output: String
            do {
                try Task.checkCancellation()
                output = String(try await browserTask(request).prefix(24_000))
            } catch {
                output = "Browser task stopped or failed. It may have partial effects. Do not retry automatically. Ask the user how to proceed."
            }
            let cancelled = Task.isCancelled
            Task { [weak self] in
                await self?.finishBrowserCall(id: id, output: output, cancelled: cancelled)
            }
        }
    }

    private func finishBrowserCall(id: String, output: String, cancelled: Bool) async {
        guard isActive else { return }
        do {
            try await send(["type": "conversation.item.create", "item": [
                "type": "function_call_output", "call_id": .string(id),
                "output": .string(cancelled ? "Cancelled; partial effects are possible. Do not retry automatically." : output),
            ], ])
            browserWork = nil
            if !cancelled {
                pendingInput = true
            }
            try await requestResponseIfReady()
        } catch { if isActive { fail() } }
    }
}
