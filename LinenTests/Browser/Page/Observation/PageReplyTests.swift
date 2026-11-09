// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// A caller waiting on a page that never answers must be released by its own cancellation, and the
/// ceiling it started must not outlive the answer. The ceilings here are an hour, so only the
/// behavior under test can end an await in time. Every wait on a caller is bounded first, and a
/// regression finishes the captured reply in a `defer`, so a failure is reported at once instead of
/// leaving a continuation parked until the ceiling.
@MainActor
@Suite(.serialized)
struct PageReplyTests {
    private static let bound = Duration.seconds(2)

    @Test func aCancelledCallerReturnsWithoutWaitingForTheCeiling() async {
        var reply: PageReply<String>?
        var finished = false
        let caller = Task { @MainActor in
            let answer = await PageReply<String>.awaiting(within: .seconds(3600)) { reply = $0 }
            finished = true
            return answer
        }
        defer {
            caller.cancel()
            reply?.finish(nil)
        }
        guard await waitUntil(timeout: Self.bound, { reply != nil }) else {
            Issue.record("the call never became pending")
            return
        }
        #expect(!finished, "the call returned before it was cancelled")

        caller.cancel()

        guard await waitUntil(timeout: Self.bound, { finished }) else {
            Issue.record("the cancelled caller is still waiting for the ceiling")
            return
        }
        #expect(await caller.value == nil)
    }

    @Test func aCallerCancelledBeforeTheCallNeverStartsThePage() async {
        var reply: PageReply<String>?
        var finished = false
        let caller = Task { @MainActor in
            let answer = await PageReply<String>.awaiting(within: .seconds(3600)) { reply = $0 }
            finished = true
            return answer
        }
        defer {
            caller.cancel()
            reply?.finish(nil)
        }
        caller.cancel()

        let returned = await waitUntil(timeout: Self.bound) { finished }
        #expect(reply == nil, "the page was started for a cancelled caller")
        guard returned else {
            Issue.record("the cancelled caller is still waiting for the ceiling")
            return
        }
        #expect(await caller.value == nil)
    }

    @Test func theCeilingTaskDoesNotRetainAnAnsweredReply() async {
        weak var reply: PageReply<Int>?
        var finished = false
        let caller = Task { @MainActor in
            let answer = await PageReply<Int>.awaiting(within: .seconds(3600)) { gate in
                reply = gate
                Task { gate.finish(1) }
            }
            finished = true
            return answer
        }
        defer {
            caller.cancel()
            reply?.finish(nil)
        }
        guard await waitUntil(timeout: Self.bound, { finished }) else {
            Issue.record("the answered caller is still waiting for the ceiling")
            return
        }

        #expect(await caller.value == 1)
        #expect(
            await waitUntil(timeout: Self.bound) { reply == nil },
            "the sleeping ceiling still holds the answered reply"
        )
    }
}
