// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// A caller waiting on a page that never answers must be released by its own cancellation, and the
/// ceiling it started must not outlive the answer. The ceilings here are an hour, so only the
/// behavior under test can end an await in time.
@MainActor
@Suite(.serialized)
struct PageReplyTests {
    @Test func aCancelledCallerReturnsWithoutWaitingForTheCeiling() async {
        var started = false
        var finished = false
        let caller = Task { @MainActor in
            let answer = await PageReply<String>.awaiting(within: .seconds(3600)) { _ in started = true }
            finished = true
            return answer
        }
        #expect(await waitUntil { started }, "the call never became pending")
        #expect(!finished, "the call returned before it was cancelled")

        caller.cancel()

        #expect(await waitUntil { finished }, "the cancelled caller is still waiting for the ceiling")
        #expect(await caller.value == nil)
    }

    @Test func aCallerCancelledBeforeTheCallNeverStartsThePage() async {
        var started = false
        let caller = Task { @MainActor in
            await PageReply<String>.awaiting(within: .seconds(3600)) { _ in started = true }
        }
        caller.cancel()

        #expect(await caller.value == nil)
        #expect(!started)
    }

    @Test func theCeilingTaskDoesNotRetainAnAnsweredReply() async {
        weak var reply: PageReply<Int>?
        let answer = await PageReply<Int>.awaiting(within: .seconds(3600)) { gate in
            reply = gate
            Task { gate.finish(1) }
        }

        #expect(answer == 1)
        #expect(await waitUntil { reply == nil }, "the sleeping ceiling still holds the answered reply")
    }
}
