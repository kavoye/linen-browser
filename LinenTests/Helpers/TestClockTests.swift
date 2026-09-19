// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@MainActor
struct TestClockTests {
    @Test func advancingTimeResumesOnlyTheDueWaiter() async throws {
        let clock = TestClock()
        let interval = Duration.seconds(1)
        let firstDeadline = clock.now + interval
        let secondDeadline = firstDeadline + interval
        var firstFinished = false
        var secondFinished = false
        let first = Task {
            try await clock.sleep(until: firstDeadline, tolerance: nil)
            firstFinished = true
        }
        let second = Task {
            try await clock.sleep(until: secondDeadline, tolerance: nil)
            secondFinished = true
        }
        defer { first.cancel(); second.cancel() }
        try #require(await waitUntil { clock.pendingCount == 2 })

        clock.advance(by: interval)
        try await first.value
        #expect(firstFinished)
        #expect(!secondFinished)
        #expect(clock.pendingCount == 1)

        clock.advance(by: interval)
        try await second.value
        #expect(secondFinished)
        #expect(clock.pendingCount == 0)
    }

    @Test func cancellationReleasesAWaiterWithoutAdvancingTime() async throws {
        let clock = TestClock()
        let original = clock.now
        let sleeper = Task { try await clock.sleep(for: .seconds(1)) }
        defer { sleeper.cancel() }
        try #require(await waitUntil { clock.pendingCount == 1 })
        sleeper.cancel()

        await #expect(throws: CancellationError.self) { try await sleeper.value }
        #expect(clock.pendingCount == 0)
        #expect(clock.now == original)
    }

    @Test func anAlreadyCancelledTaskNeverRegistersAWaiter() async {
        let clock = TestClock()
        let sleeper = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await clock.sleep(for: .seconds(1))
        }
        await #expect(throws: CancellationError.self) { try await sleeper.value }
        #expect(clock.pendingCount == 0)
    }
}
