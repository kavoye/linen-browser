// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AVFAudio

@MainActor
final class AudioCaptureService {
    private var engine: AVAudioEngine?
    private var continuation: AsyncStream<CapturedAudio>.Continuation?
    private let ducker = OutputDucker()

    func start(targetFormat: AVAudioFormat) throws -> AsyncStream<CapturedAudio> {
        stop()
        ducker.duck()
        var opened = false
        defer { if !opened { ducker.restore() } }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let converter = AudioSampleConverter(from: inputFormat, to: targetFormat) else {
            throw AudioCaptureError.converterUnavailable
        }

        let (stream, continuation) = AsyncStream.makeStream(of: CapturedAudio.self)
        let tap = TapContext(converter: converter, continuation: continuation)

        // `@Sendable` keeps the closure out of the app's default main-actor
        // isolation. Core Audio invokes it on a realtime queue, where a
        // main-actor closure traps the isolation assertion.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { @Sendable buffer, _ in
            tap.process(buffer)
        }

        engine.prepare()
        try engine.start()

        self.engine = engine
        self.continuation = continuation
        opened = true
        return stream
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        continuation?.finish()
        continuation = nil
        ducker.restore()
        MicLevel.shared.reset()
    }
}

enum AudioCaptureError: Error {
    case converterUnavailable
}

private nonisolated final class TapContext: @unchecked Sendable {
    private let converter: AudioSampleConverter
    private let continuation: AsyncStream<CapturedAudio>.Continuation

    init(
        converter: AudioSampleConverter,
        continuation: AsyncStream<CapturedAudio>.Continuation
    ) {
        self.converter = converter
        self.continuation = continuation
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        if let level = AudioSampleConverter.level(of: buffer) {
            MicLevel.shared.record(rms: level)
        }
        guard let converted = converter.convert(buffer) else { return }
        continuation.yield(CapturedAudio(buffer: converted))
    }
}
