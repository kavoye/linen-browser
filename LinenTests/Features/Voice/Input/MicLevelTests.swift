// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

struct MicLevelTests {
    private func settled(_ meter: MicLevel, at rms: Double, steps: Int = 200) -> Double {
        for _ in 0..<steps {
            meter.record(rms: rms)
        }
        return meter.level
    }

    @Test func silenceReadsAsNothing() {
        let meter = MicLevel()
        #expect(meter.level == 0)
    }

    @Test func theLevelNeverLeavesTheRangeTheBarsAreDrawnIn() {
        let meter = MicLevel()
        for rms in [0.0, 0.001, 0.05, 0.125, 0.5, 1.0, 40.0] {
            for _ in 0..<50 {
                meter.record(rms: rms)
            }
            #expect(meter.level >= 0 && meter.level <= 1, "\(rms)")
        }
    }

    @Test func nonsenseFromTheTapIsFlooredRatherThanDrawn() {
        let meter = MicLevel()
        _ = settled(meter, at: 0.5)

        for _ in 0..<200 {
            meter.record(rms: -5)
        }

        #expect(meter.level >= 0)
        #expect(meter.level < 0.01)
    }

    @Test func loudSpeechReachesTheTopWithoutClipping() {
        let meter = MicLevel()
        #expect(settled(meter, at: 0.125) > 0.99)
        #expect(settled(MicLevel(), at: 1.0) <= 1)
    }

    @Test func aLouderSoundSettlesHigherThanAQuieterOne() {
        #expect(settled(MicLevel(), at: 0.02) < settled(MicLevel(), at: 0.06))
        #expect(settled(MicLevel(), at: 0.06) < settled(MicLevel(), at: 0.1))
    }

    // MARK: - How it moves

    @Test func theLevelRisesFasterThanItFalls() {
        let rising = MicLevel()
        rising.record(rms: 0.125)
        let afterOneRise = rising.level

        let falling = MicLevel()
        _ = settled(falling, at: 0.125)
        let peak = falling.level
        falling.record(rms: 0)
        let droppedBy = peak - falling.level

        #expect(afterOneRise > droppedBy)
    }

    @Test func oneLoudSampleDoesNotSnapStraightToTheTop() {
        let meter = MicLevel()
        meter.record(rms: 1.0)
        #expect(meter.level < 1)
        #expect(meter.level > 0)
    }

    @Test func theLevelDecaysTowardsSilenceWhenTheTalkingStops() {
        let meter = MicLevel()
        _ = settled(meter, at: 0.125)
        let peak = meter.level

        meter.record(rms: 0)
        let afterOne = meter.level
        meter.record(rms: 0)

        #expect(afterOne < peak)
        #expect(meter.level < afterOne)
    }

    @Test func aShortGapDoesNotEmptyTheBars() {
        let meter = MicLevel()
        _ = settled(meter, at: 0.125)

        for _ in 0..<3 {
            meter.record(rms: 0)
        }

        #expect(meter.level > 0.4)
    }

    @Test func resettingEmptiesItAtOnce() {
        let meter = MicLevel()
        _ = settled(meter, at: 0.125)

        meter.reset()

        #expect(meter.level == 0)
    }

    @Test func aMeterKeepsReadingAfterAReset() {
        let meter = MicLevel()
        meter.reset()

        meter.record(rms: 0.125)

        #expect(meter.level > 0)
    }
}
