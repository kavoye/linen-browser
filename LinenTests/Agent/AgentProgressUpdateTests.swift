// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@MainActor
struct AgentProgressUpdateTests {
    @Test func commentaryIsInterleavedWithWorkAndSeparateFromTheFinalAnswer() async throws {
        let fixture = HarnessFixture([
            .commentary("I'll inspect the form first.", ["readPage"]),
            .progress("The page requires one more field. I'll fill it next."),
            .calls(["typeOnPage"]), .text("Finished.")
        ])
        fixture.state.output = { _ in
            let id = try #require(fixture.log.latestTrace(forTab: fixture.tabID)?.id)
            let step = fixture.log.beginTool(taskID: id, name: "readPage", title: "Read page")
            fixture.log.completeTool(taskID: id, stepID: step, detail: "")
            return "Verified page state"
        }
        var sawUpdateWhileRunning = false
        fixture.agent.onEvaluationEvent = { event in
            if event.kind == "tool_proposed" {
                sawUpdateWhileRunning = fixture.log.latestTrace(forTab: fixture.tabID)?.progressUpdates.isEmpty == false
            }
        }
        await fixture.run()
        let trace = try #require(fixture.log.latestTrace(forTab: fixture.tabID))
        #expect(sawUpdateWhileRunning)
        #expect(trace.progressUpdates.map(\.afterStepCount) == [0, 1])
        #expect(trace.response == "Finished.")
        #expect(fixture.state.calls == 2)
        #expect(trace.diagnostics.toolCalls == 2)
        #expect(trace.steps.count == 2)
    }

    @Test func updatesSurviveReloadOnlyInPrivateConversationStorage() async throws {
        let privateText = "fixture-private-progress-account-42"
        let fixture = HarnessFixture([.progress(privateText), .calls(["readPage"]), .text("Done.")])
        await fixture.run()
        let restored = ConversationLog(database: fixture.database)
        let trace = try #require(restored.latestTrace(forTab: fixture.tabID))
        #expect(trace.progressUpdates.first?.text == privateText)
        #expect(!trace.diagnostics.exported().contains(privateText))
        #expect(!trace.steps.contains { $0.detail?.contains(privateText) == true || $0.title.contains(privateText) })
        #expect(trace.response == "Done.")
    }

    @Test func consecutiveDuplicateUpdatesAreNotRepeated() async throws {
        let fixture = HarnessFixture([
            .progress("I'll inspect the page."), .progress("I'll inspect the page."),
            .calls(["readPage"]), .text("Done.")
        ])
        await fixture.run()
        #expect(fixture.log.latestTrace(forTab: fixture.tabID)?.progressUpdates.count == 1)
    }

    @Test func newTurnDoesNotReplayOldProgress() async throws {
        let fixture = HarnessFixture([.progress("I'll check."), .calls(["readPage"]), .text("Done."), .text("Yes.")])
        await fixture.run()
        await fixture.run("Is that all?")
        #expect(fixture.log.latestTrace(forTab: fixture.tabID)?.progressUpdates.isEmpty == true)
    }

    @Test func aSimpleAnswerDoesNotInventProgress() async throws {
        let fixture = HarnessFixture([.text("Hello.")])
        await fixture.run("Hello")
        #expect(fixture.log.latestTrace(forTab: fixture.tabID)?.progressUpdates.isEmpty == true)
        #expect(fixture.model.requests.count == 1)
    }

    @Test func progressWithoutActualWorkCannotLoopForever() async throws {
        let fixture = HarnessFixture(Array(repeating: .progress("Working on it."), count: 10))
        await fixture.run()
        #expect(fixture.log.latestTrace(forTab: fixture.tabID)?.stopReason == .noProgress)
        #expect(fixture.state.calls == 0)
    }
}
