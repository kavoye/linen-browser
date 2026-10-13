// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AVFAudio
import Foundation

@MainActor
final class OpenAITranscriberEngine: TranscriberEngine {
    private(set) var bestFormat: AVAudioFormat?
    private let client: OpenAIVoiceClient
    private var run: OpenAITranscriptionRun?

    init(client: OpenAIVoiceClient) {
        self.client = client
    }

    func prepare() throws {
        try client.settings.validate()
        bestFormat = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)
        guard bestFormat != nil else { throw OpenAIVoiceFailure.invalidAudio }
    }

    func startSession(input: AsyncStream<CapturedAudio>) -> AsyncThrowingStream<TranscriptUpdate, any Error> {
        let run = OpenAITranscriptionRun(client: client)
        self.run = run
        return run.start(input)
    }

    func finishSession() async throws {
        guard let current = run else { return }
        defer { if run === current { run = nil } }
        try await current.task?.value
    }

    func cancelSession() async {
        guard let current = run else { return }
        run = nil
        await current.cancel()
    }
}

@MainActor
private final class OpenAITranscriptionRun {
    let client: OpenAIVoiceClient
    var task: Task<Void, any Error>?
    private var socket: (any OpenAISocketConnection)?

    init(client: OpenAIVoiceClient) {
        self.client = client
    }

    func start(_ input: AsyncStream<CapturedAudio>) -> AsyncThrowingStream<TranscriptUpdate, any Error> {
        let (stream, continuation) = AsyncThrowingStream<TranscriptUpdate, any Error>.makeStream()
        task = Task {
            do {
                let socket = try client.makeSocket()
                self.socket = socket
                let lifetime = deadline(socket, after: .seconds(300))
                defer { lifetime.cancel() }
                try await configure(socket)
                let receiver = Task {
                    do { try await self.receive(socket, continuation: continuation) } catch {
                        self.task?.cancel()
                        await socket.close()
                        throw error
                    }
                }
                defer { receiver.cancel() }
                do {
                    var sampleBytes = 0
                    for await captured in input {
                        try Task.checkCancellation()
                        let data = try OpenAIPCM.encode(captured.buffer)
                        sampleBytes += data.count
                        guard sampleBytes <= 24_000 * 2 * 300 else { throw OpenAIVoiceFailure.tooLong }
                        if !data.isEmpty {
                            try await socket.send(["type": "input_audio_buffer.append", "audio": .string(data.base64EncodedString())])
                        }
                    }
                    try Task.checkCancellation()
                    if sampleBytes < 4_800 {
                        receiver.cancel()
                        await socket.close()
                        continuation.yield(.init(text: "", isFinal: true))
                    } else {
                        try await socket.send(["type": "input_audio_buffer.commit"])
                        let finishing = deadline(socket, after: .seconds(20))
                        defer { finishing.cancel() }
                        try await receiver.value
                    }
                    await socket.close()
                    self.socket = nil
                    continuation.finish()
                } catch {
                    receiver.cancel()
                    await socket.close()
                    throw error
                }
            } catch {
                await socket?.close()
                socket = nil
                continuation.finish(throwing: error)
                throw error
            }
        }
        continuation.onTermination = { [weak self] termination in
            if case .cancelled = termination {
                Task { @MainActor in await self?.cancel() }
            }
        }
        return stream
    }

    func cancel() async {
        task?.cancel()
        await socket?.close()
        _ = try? await task?.value
        socket = nil
    }

    private func deadline(_ socket: any OpenAISocketConnection, after delay: Duration) -> Task<Void, Never> {
        Task {
            do { try await Task.sleep(for: delay) } catch { return }
            await socket.close()
        }
    }

    private func configure(_ socket: any OpenAISocketConnection) async throws {
        let timeout = deadline(socket, after: .seconds(15))
        defer { timeout.cancel() }
        try await socket.send(client.transcriptionConfiguration)
        while true {
            try Task.checkCancellation()
            let event = try await socket.receive()
            if event["type"] == "session.updated" || event["type"] == "transcription_session.updated" {
                return
            }
            if event["type"] == "error" {
                throw OpenAIVoiceFailure.configuration
            }
        }
    }

    private func receive(_ socket: any OpenAISocketConnection,
                         continuation: AsyncThrowingStream<TranscriptUpdate, any Error>.Continuation) async throws {
        var assembler = OpenAITranscriptAssembler()
        while true {
            try Task.checkCancellation()
            let event = try await socket.receive()
            if let update = try assembler.receive(event) {
                continuation.yield(update)
                if update.isFinal {
                    return
                }
            }
        }
    }
}

nonisolated struct OpenAITranscriptAssembler {
    private var partials: [String: String] = [:]
    private var completed: [String: String] = [:]
    private var committedID: String?

    mutating func receive(_ event: OpenAIJSON) throws -> TranscriptUpdate? {
        switch event["type"].string {
        case "input_audio_buffer.committed":
            committedID = event["item_id"].string
        case "conversation.item.input_audio_transcription.delta":
            guard let id = event["item_id"].string, let delta = event["delta"].string else { throw OpenAIVoiceFailure.transcription }
            partials[id, default: ""] += delta
            return .init(text: partials[id] ?? "", isFinal: false)
        case "conversation.item.input_audio_transcription.completed":
            guard let id = event["item_id"].string, let text = event["transcript"].string else { throw OpenAIVoiceFailure.transcription }
            completed[id] = text
        case "error", "conversation.item.input_audio_transcription.failed":
            throw OpenAIVoiceFailure.transcription
        default:
            break
        }
        if let id = committedID, let text = completed[id] {
            return .init(text: text, isFinal: true)
        }
        return nil
    }
}

nonisolated enum OpenAIPCM {
    static func encode(_ buffer: AVAudioPCMBuffer) throws -> Data {
        guard buffer.format.sampleRate == 24_000, buffer.format.channelCount == 1,
              let samples = buffer.floatChannelData?[0] else { throw OpenAIVoiceFailure.invalidAudio }
        var data = Data(capacity: Int(buffer.frameLength) * 2)
        for index in 0..<Int(buffer.frameLength) {
            let sample = samples[index]
            guard sample.isFinite else { throw OpenAIVoiceFailure.invalidAudio }
            let value = Int16((min(1, max(-1, sample)) * 32_767).rounded())
            let bits = UInt16(bitPattern: value)
            data.append(UInt8(truncatingIfNeeded: bits))
            data.append(UInt8(truncatingIfNeeded: bits >> 8))
        }
        return data
    }
}
