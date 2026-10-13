// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AVFAudio
import CoreAudio

@MainActor
final class AudioCaptureService {
    private let hardware = CaptureHardware()
    private let ducker = OutputDucker()
    private let conversational: Bool
    private let processesVoice: Bool
    private var generation = 0
    private(set) var usesEchoCancellation = false

    init(conversational: Bool = false, processesVoice: Bool? = nil) {
        self.conversational = conversational
        self.processesVoice = processesVoice ?? conversational
    }

    func start(targetFormat: AVAudioFormat) async throws -> AsyncStream<CapturedAudio> {
        stop()
        let starting = generation
        if !conversational {
            ducker.duck()
        }
        do {
            let opened = try await hardware.start(targetFormat: targetFormat, processesVoice: processesVoice, bounded: conversational)
            guard generation == starting, !Task.isCancelled else {
                if generation == starting {
                    stop()
                }
                throw CancellationError()
            }
            usesEchoCancellation = opened.processesVoice
            return opened.stream
        } catch {
            if generation == starting {
                stop()
            }
            throw error
        }
    }

    func stop() {
        generation &+= 1
        hardware.stop()
        ducker.restore()
        MicLevel.shared.reset()
    }

    func setMuted(_ muted: Bool) {
        hardware.setMuted(muted)
    }
}

private nonisolated final class CaptureHardware: @unchecked Sendable {
    private static let queue = DispatchQueue(label: "com.kavoye.linen.audio-capture", qos: .default)
    private var engine: AVAudioEngine?
    private var deviceCapture: DeviceAudioCapture?
    private var continuation: AsyncStream<CapturedAudio>.Continuation?

    struct OpenedCapture: Sendable {
        let stream: AsyncStream<CapturedAudio>
        let processesVoice: Bool
    }

    func start(targetFormat: AVAudioFormat, processesVoice: Bool, bounded: Bool) async throws -> OpenedCapture {
        try await withCheckedThrowingContinuation { result in
            Self.queue.async {
                do {
                    let inputDevice = try Self.defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
                    do {
                        let stream = try self.open(targetFormat: targetFormat, processesVoice: processesVoice, bounded: bounded, inputDevice: inputDevice)
                        result.resume(returning: OpenedCapture(stream: stream, processesVoice: processesVoice))
                    } catch {
                        guard processesVoice else { throw error }
                        let stream = try self.openDevice(targetFormat: targetFormat, inputDevice: inputDevice)
                        result.resume(returning: OpenedCapture(stream: stream, processesVoice: false))
                    }
                } catch { result.resume(throwing: error) }
            }
        }
    }

    private func openDevice(targetFormat: AVAudioFormat, inputDevice: AudioDeviceID) throws -> AsyncStream<CapturedAudio> {
        close()
        let (stream, continuation) = AsyncStream.makeStream(of: CapturedAudio.self, bufferingPolicy: .bufferingOldest(32))
        let capture = try DeviceAudioCapture(deviceID: inputDevice, format: targetFormat, continuation: continuation)
        deviceCapture = capture
        self.continuation = continuation
        do { try capture.start() } catch {
            close()
            throw error
        }
        return stream
    }

    private static func defaultDevice(_ selector: AudioObjectPropertySelector) throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr, device != kAudioObjectUnknown else { throw AudioCaptureError.converterUnavailable }
        return device
    }

    private func open(targetFormat: AVAudioFormat, processesVoice: Bool, bounded: Bool, inputDevice: AudioDeviceID) throws -> AsyncStream<CapturedAudio> {
        close()
        let engine = AVAudioEngine()
        self.engine = engine
        var opened = false
        defer { if !opened { close() } }
        let input = engine.inputNode
        try input.auAudioUnit.setDeviceID(inputDevice)
        if processesVoice {
            try input.setVoiceProcessingEnabled(true)
            input.isVoiceProcessingInputMuted = false
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioCaptureError.converterUnavailable }
        if processesVoice {
            engine.connect(input, to: engine.mainMixerNode, format: format)
            engine.mainMixerNode.outputVolume = 0
        }
        guard let converter = AudioSampleConverter(from: format, to: targetFormat) else {
            throw AudioCaptureError.converterUnavailable
        }
        let (stream, continuation) = AsyncStream.makeStream(of: CapturedAudio.self, bufferingPolicy: bounded ? .bufferingOldest(32) : .unbounded)
        let tap = TapContext(converter: converter, continuation: continuation)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { @Sendable buffer, _ in
            tap.process(buffer)
        }
        self.engine = engine
        self.continuation = continuation
        engine.prepare()
        try engine.start()
        opened = true
        return stream
    }

    func stop() {
        Self.queue.async { self.close() }
    }

    private func close() {
        deviceCapture?.stop()
        deviceCapture = nil
        engine?.stop()
        if continuation != nil {
            engine?.inputNode.removeTap(onBus: 0)
        }
        if let input = engine?.inputNode, input.isVoiceProcessingEnabled {
            try? input.setVoiceProcessingEnabled(false)
        }
        engine = nil
        continuation?.finish()
        continuation = nil
        MicLevel.shared.reset()
    }

    func setMuted(_ muted: Bool) {
        Self.queue.async {
            self.deviceCapture?.setMuted(muted)
            if let input = self.engine?.inputNode, input.isVoiceProcessingEnabled {
                input.isVoiceProcessingInputMuted = muted
            }
        }
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
        if case .dropped = continuation.yield(CapturedAudio(buffer: converted)) {
            continuation.finish()
        }
    }
}
