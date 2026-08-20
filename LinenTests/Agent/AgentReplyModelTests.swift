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
        let reply = AgentReplyModel()
        reply.beginStream()
        reply.setActivity("Searching")
        reply.update(text: "Done")

        reply.endStream(retainFor: 0)
        #expect(!reply.isStreaming)
        #expect(reply.activity == nil)
        #expect(reply.text == "Done")

        for _ in 0..<100 {
            if reply.text == nil {
                break
            }
            await Task.yield()
        }
        #expect(reply.text == nil)
        #expect(!reply.isVisible)
    }

    @Test func aNewStreamCancelsTheOldFade() async {
        let reply = AgentReplyModel()
        reply.beginStream()
        reply.update(text: "Old reply")
        reply.endStream(retainFor: 0)

        reply.beginStream()
        reply.update(text: "New reply")
        for _ in 0..<100 {
            await Task.yield()
        }

        #expect(reply.isStreaming)
        #expect(reply.text == "New reply")
    }
}
