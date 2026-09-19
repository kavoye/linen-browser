// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct OpenAIVoiceSettings: Codable, Equatable, Sendable {
    var usesOpenAI = true
    var transcriptionModel = "gpt-live-transcribe"
    var conversationModel = "gpt-realtime-2.1"
    var conversationVoice = "cedar"
    var speechModel = "gpt-4o-mini-tts"
    var voice = "cedar"
    var speed = 1.0
    var instructions = "Speak clearly and naturally."

    init() {}

    private enum CodingKeys: String, CodingKey {
        case usesOpenAI, transcriptionModel, speechModel, voice, speed, instructions, conversationModel, conversationVoice
    }

    init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        usesOpenAI = try fields.decodeIfPresent(Bool.self, forKey: .usesOpenAI) ?? true
        transcriptionModel = try fields.decodeIfPresent(String.self, forKey: .transcriptionModel) ?? "gpt-live-transcribe"
        speechModel = try fields.decodeIfPresent(String.self, forKey: .speechModel) ?? "gpt-4o-mini-tts"
        conversationModel = try fields.decodeIfPresent(String.self, forKey: .conversationModel) ?? "gpt-realtime-2.1"
        conversationVoice = try fields.decodeIfPresent(String.self, forKey: .conversationVoice) ?? "cedar"
        voice = try fields.decodeIfPresent(String.self, forKey: .voice) ?? "cedar"
        speed = try fields.decodeIfPresent(Double.self, forKey: .speed) ?? 1
        instructions = try fields.decodeIfPresent(String.self, forKey: .instructions) ?? "Speak clearly and naturally."
    }

    func validate() throws {
        guard !transcriptionModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !speechModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !voice.isEmpty, speed.isFinite, (0.25...4).contains(speed), instructions.count <= 2_000
        else { throw OpenAIVoiceFailure.configuration }
    }
}

nonisolated enum OpenAIVoiceFailure: Error {
    case configuration, invalidAudio, interrupted, transcription, speech, tooLong
}

nonisolated struct OpenAIVoiceClient: Sendable {
    let transport: any OpenAITransport
    let settings: OpenAIVoiceSettings
    let makeSocket: @Sendable () throws -> any OpenAISocketConnection

    init(endpoint: URL, key: String, settings: OpenAIVoiceSettings) {
        let http = OpenAIHTTPTransport(baseURL: endpoint, apiKey: key)
        transport = http
        self.settings = settings
        makeSocket = {
            guard !key.isEmpty else { throw OpenAIVoiceFailure.configuration }
            let request = try http.urlRequest(.init(path: ["realtime"], method: "GET", query: ["intent": "transcription"]))
            return try OpenAISocket(request: request)
        }
    }

    init(transport: any OpenAITransport, settings: OpenAIVoiceSettings,
         makeSocket: @escaping @Sendable () throws -> any OpenAISocketConnection) {
        self.transport = transport
        self.settings = settings
        self.makeSocket = makeSocket
    }

    func speech(_ text: String, onUsage: @escaping @Sendable (OpenAIJSON) async -> Void = { _ in }) -> AsyncThrowingStream<Data, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try settings.validate()
                    guard !text.isEmpty, text.unicodeScalars.count <= 4_096 else { throw OpenAIVoiceFailure.tooLong }
                    var body: OpenAIJSON = [
                        "model": .string(settings.speechModel), "voice": .string(settings.voice), "input": .string(text),
                        "response_format": "pcm", "stream_format": "sse", "speed": .number(settings.speed),
                    ]
                    if !settings.instructions.isEmpty {
                        body["instructions"] = .string(settings.instructions)
                    }
                    var receivedAudio = false
                    for try await event in transport.events(.init(path: ["audio", "speech"], body: try body.data())) {
                        try Task.checkCancellation()
                        switch event.type {
                        case "speech.audio.delta":
                            guard let encoded = event.payload["audio"].string, let data = Data(base64Encoded: encoded) else {
                                throw OpenAIVoiceFailure.invalidAudio
                            }
                            if !data.isEmpty {
                                receivedAudio = true
                                continuation.yield(data)
                            }
                        case "speech.audio.done":
                            guard receivedAudio else { throw OpenAIVoiceFailure.invalidAudio }
                            await onUsage(event.payload["usage"])
                            continuation.finish()
                            return
                        case "error":
                            throw OpenAIVoiceFailure.speech
                        default:
                            break
                        }
                    }
                    throw OpenAIVoiceFailure.interrupted
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    var transcriptionConfiguration: OpenAIJSON {
        let input: OpenAIJSON = [
            "format": ["type": "audio/pcm", "rate": 24_000],
            "transcription": ["model": .string(settings.transcriptionModel)], "turn_detection": .null,
        ]
        return ["type": "session.update", "session": ["type": "transcription", "audio": ["input": input]]]
    }
}
