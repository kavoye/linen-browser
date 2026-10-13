// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AVFoundation
import CoreAudio

nonisolated final class DeviceAudioCapture: @unchecked Sendable {
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let samples: DeviceAudioSamples

    init(deviceID: AudioDeviceID, format: AVAudioFormat, continuation: AsyncStream<CapturedAudio>.Continuation) throws {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID,
                                                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid) == noErr,
              let uid else { throw AudioCaptureError.converterUnavailable }
        let identifier = uid.takeRetainedValue() as String
        guard let device = AVCaptureDevice(uniqueID: identifier) else { throw AudioCaptureError.converterUnavailable }
        samples = try DeviceAudioSamples(format: format, continuation: continuation)
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input), session.canAddOutput(output) else { throw AudioCaptureError.converterUnavailable }
        session.addInput(input)
        session.addOutput(output)
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: 1, AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsNonInterleaved: true,
        ]
        output.setSampleBufferDelegate(samples, queue: DispatchQueue(label: "com.kavoye.linen.microphone-samples", qos: .default))
    }

    func start() throws {
        session.startRunning()
        guard session.isRunning else { throw AudioCaptureError.converterUnavailable }
    }

    func stop() {
        session.stopRunning()
        output.setSampleBufferDelegate(nil, queue: nil)
    }

    func setMuted(_ muted: Bool) {
        output.connection(with: .audio)?.isEnabled = !muted
    }
}

private nonisolated final class DeviceAudioSamples: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let format: AVAudioFormat
    private let continuation: AsyncStream<CapturedAudio>.Continuation
    private var pending: AVAudioPCMBuffer
    private let capacity: AVAudioFrameCount

    init(format: AVAudioFormat, continuation: AsyncStream<CapturedAudio>.Continuation) throws {
        self.format = format
        self.continuation = continuation
        capacity = AVAudioFrameCount(format.sampleRate / 10)
        guard let pending = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { throw AudioCaptureError.converterUnavailable }
        self.pending = pending
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let count = CMSampleBufferGetNumSamples(sampleBuffer)
        guard count > 0, count <= Int(format.sampleRate),
              let description = CMSampleBufferGetFormatDescription(sampleBuffer) else { continuation.finish(); return }
        let actual = AVAudioFormat(cmAudioFormatDescription: description)
        guard actual.sampleRate == format.sampleRate, actual.channelCount == 1, actual.commonFormat == .pcmFormatFloat32,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else {
            continuation.finish()
            return
        }
        buffer.frameLength = AVAudioFrameCount(count)
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(count), into: buffer.mutableAudioBufferList) == noErr,
              let source = buffer.floatChannelData?[0] else { continuation.finish(); return }
        var offset = 0
        while offset < count {
            let copied = min(count - offset, Int(capacity - pending.frameLength))
            pending.floatChannelData![0].advanced(by: Int(pending.frameLength)).update(from: source.advanced(by: offset), count: copied)
            pending.frameLength += AVAudioFrameCount(copied)
            offset += copied
            if pending.frameLength == capacity {
                MicLevel.shared.record(rms: AudioSampleConverter.level(of: pending) ?? 0)
                if case .dropped = continuation.yield(CapturedAudio(buffer: pending)) {
                    continuation.finish()
                    return
                }
                guard let next = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { continuation.finish(); return }
                pending = next
            }
        }
    }
}
