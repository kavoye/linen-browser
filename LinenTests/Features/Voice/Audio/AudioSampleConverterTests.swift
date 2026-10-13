// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AVFAudio
import Testing

@testable import Linen

@Suite
struct AudioSampleConverterTests {
    @Test func downsamplingKeepsAudioAndShortensTheBuffer() throws {
        let input = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let target = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let converter = try #require(AudioSampleConverter(from: input, to: target))
        let tone = try #require(Self.tone(format: input, frames: 4_800, amplitude: 0.5))

        let converted = try #require(converter.convert(tone))

        #expect(converted.format.sampleRate == 16_000)
        #expect(converted.frameLength > 0)
        #expect(converted.frameLength < tone.frameLength)
        let level = try #require(AudioSampleConverter.level(of: converted))
        #expect(level > 0.2)
    }

    @Test func aMatchingFormatPassesEveryFrameThrough() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let converter = try #require(AudioSampleConverter(from: format, to: format))
        let tone = try #require(Self.tone(format: format, frames: 1_024, amplitude: 0.5))

        let converted = try #require(converter.convert(tone))

        #expect(converted.frameLength == tone.frameLength)
    }

    @Test func anEmptyBufferConvertsToNothing() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let converter = try #require(AudioSampleConverter(from: format, to: format))
        let empty = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
        empty.frameLength = 0

        #expect(converter.convert(empty) == nil)
    }

    @Test func aConverterSurvivesRepeatedBuffers() throws {
        let input = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let target = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let converter = try #require(AudioSampleConverter(from: input, to: target))

        for _ in 0..<8 {
            let tone = try #require(Self.tone(format: input, frames: 4_410, amplitude: 0.5))
            let converted = try #require(converter.convert(tone))
            #expect(converted.frameLength > 0)
        }
    }

    @Test func aFullScaleToneMeasuresNearTheRootMeanSquareOfASine() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let tone = try #require(Self.tone(format: format, frames: 16_000, amplitude: 1))

        let level = try #require(AudioSampleConverter.level(of: tone))

        #expect(abs(level - 0.707) < 0.01)
    }

    @Test func silenceMeasuresZero() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let silence = try #require(Self.tone(format: format, frames: 1_024, amplitude: 0))

        #expect(AudioSampleConverter.level(of: silence) == 0)
    }

    @Test func anEmptyBufferHasNoLevel() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let empty = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
        empty.frameLength = 0

        #expect(AudioSampleConverter.level(of: empty) == nil)
    }

    private static func tone(
        format: AVAudioFormat,
        frames: AVAudioFrameCount,
        amplitude: Float
    ) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = frames
        let step = 2 * Float.pi * 440 / Float(format.sampleRate)
        for index in 0..<Int(frames) {
            samples[index] = amplitude * sin(step * Float(index))
        }
        return buffer
    }
}
