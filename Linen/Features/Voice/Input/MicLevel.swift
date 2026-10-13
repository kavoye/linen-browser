// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

/// Core Audio's realtime tap writes this. The type stays `nonisolated`
/// because a main-actor write from the tap traps the isolation assertion.
nonisolated final class MicLevel: @unchecked Sendable {
    static let shared = MicLevel()

    private let state = OSAllocatedUnfairLock(initialState: 0.0)

    var level: Double {
        state.withLock { $0 }
    }

    func record(rms: Double) {
        let normalized = min(1, max(0, rms * 8))
        let shaped = pow(normalized, 0.6)
        state.withLock { current in
            current += (shaped - current) * (shaped > current ? 0.55 : 0.16)
        }
    }

    func reset() {
        state.withLock { $0 = 0 }
    }
}
