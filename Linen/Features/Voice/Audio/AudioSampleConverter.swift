// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AVFAudio

nonisolated struct AudioSampleConverter {
    private let converter: AVAudioConverter
    private let targetFormat: AVAudioFormat

    init?(from inputFormat: AVAudioFormat, to targetFormat: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            return nil
        }
        self.converter = converter
        self.targetFormat = targetFormat
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return nil
        }

        let feeder = SingleShotFeeder(buffer: buffer)
        var conversionError: NSError?
        let status = converter.convert(to: converted, error: &conversionError) { _, outStatus in
            guard let next = feeder.take() else {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            return next
        }

        guard status != .error, converted.frameLength > 0 else { return nil }
        return converted
    }

    static func level(of buffer: AVAudioPCMBuffer) -> Double? {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return nil }
        var sumOfSquares: Float = 0
        for index in 0..<Int(buffer.frameLength) {
            let sample = samples[index]
            sumOfSquares += sample * sample
        }
        return Double((sumOfSquares / Float(buffer.frameLength)).squareRoot())
    }
}

private nonisolated final class SingleShotFeeder: @unchecked Sendable {
    private var supplied = false
    private let buffer: AVAudioPCMBuffer

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func take() -> AVAudioPCMBuffer? {
        if supplied {
            return nil
        }
        supplied = true
        return buffer
    }
}
