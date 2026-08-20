// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Testing

@testable import Linen

struct AudioModelTests {
    @Test func microphoneLevelShapesAndSmoothsSamples() {
        let level = MicLevel()

        level.record(rms: 1)
        #expect(abs(level.level - 0.55) < 0.000_001)

        level.record(rms: 0)
        #expect(abs(level.level - 0.462) < 0.000_001)
    }

    @Test func microphoneLevelClampsInputRange() {
        let level = MicLevel()

        level.record(rms: -1)
        #expect(level.level == 0)

        level.record(rms: .infinity)
        #expect(level.level.isFinite)
        #expect(level.level <= 1)
    }

    @Test func microphoneLevelCanBeReset() {
        let level = MicLevel()
        level.record(rms: 0.5)

        level.reset()

        #expect(level.level == 0)
    }
}
