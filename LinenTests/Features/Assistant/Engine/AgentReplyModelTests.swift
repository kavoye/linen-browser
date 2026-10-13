// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@MainActor
struct AgentReplyModelTests {
    @Test func streamStateCanBeUpdatedAndCleared() {
        let reply = AgentReplyModel()

        reply.beginStream()
        #expect(reply.isStreaming)
        #expect(!reply.isVisible)

        reply.setActivity("Reading page")
        reply.update(text: "Working on it")
        #expect(reply.activity == "Reading page")
        #expect(reply.text == "Working on it")
        #expect(reply.isVisible)

        reply.clear()
        #expect(!reply.isStreaming)
        #expect(!reply.isVisible)
    }

    @Test func endingAStreamRetainsThenClearsTheReply() async {
        let clock = TestClock()
        let reply = AgentReplyModel(clock: clock)
        reply.beginStream()
        reply.setActivity("Searching")
        reply.update(text: "Done")

        reply.endStream(retainFor: 1)
        #expect(!reply.isStreaming)
        #expect(reply.activity == nil)
        #expect(reply.text == "Done")

        #expect(await waitUntil { clock.pendingCount == 1 })
        clock.advance(by: .seconds(1))
        #expect(await waitUntil { reply.text == nil })
        #expect(!reply.isVisible)
    }

    @Test func aNewStreamCancelsTheOldFade() async {
        let clock = TestClock()
        let retention = Duration.seconds(1)
        let reply = AgentReplyModel(clock: clock)
        reply.beginStream()
        reply.update(text: "Old reply")
        reply.endStream(retainFor: 1)
        #expect(await waitUntil { clock.pendingCount == 1 })

        reply.beginStream()
        reply.update(text: "New reply")
        #expect(await waitUntil { clock.pendingCount == 0 })
        clock.advance(by: retention)

        #expect(reply.isStreaming)
        #expect(reply.text == "New reply")
    }
}
