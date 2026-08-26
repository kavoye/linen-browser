// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Waits for a condition instead of for a number of ticks.
///
/// A loop of `n` sleeps spends the same time whatever the machine is doing, so
/// its budget has to cover the slowest run: a release job builds an archive in
/// the same job as the tests, and a count that passes on a quiet Mac runs out
/// there. This returns as soon as the condition holds, which makes a generous
/// timeout free on a quiet machine.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(25),
    tick: Duration = .milliseconds(20),
    _ condition: () async -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() {
            return true
        }
        try? await Task.sleep(for: tick)
    }
    return await condition()
}
