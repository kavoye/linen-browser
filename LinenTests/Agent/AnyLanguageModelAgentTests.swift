// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import Testing

@testable import Linen

@MainActor
@Suite(.serialized)
struct AnyLanguageModelAgentTests {
    @Test func successfulAnswerCompletesTheTraceBeforeCoordinatorCleanup() async throws {
        let fixture = HarnessFixture([.text("Done.")])
        let taskID = fixture.log.beginTask("Finish the task", tabID: fixture.tabID)

        await fixture.agent.run(
            utterance: "Finish the task",
            task: .init(id: taskID, tabID: fixture.tabID),
            into: fixture.reply,
            speech: fixture.speech
        )

        let trace = try #require(fixture.log.latestTrace(forTab: fixture.tabID))
        #expect(trace.state == .completed)
        #expect(!trace.canContinue)
        #expect(trace.response == "Done.")
    }

    @Test func unchangedPageReadsWithNewObservationIDsRecoverThenPause() async throws {
        let state = HarnessToolState()
        state.output = { "PAGE TEXT:\nPending\n\nCONTROLS:\n\nobservationID: read\($0)" }
        let fixture = HarnessFixture(Array(repeating: .calls(["readPage"]), count: 20), state: state)
        await fixture.run("Wait for the page to change")
        let trace = try #require(fixture.log.latestTrace(forTab: fixture.tabID))
        #expect(trace.stopReason == .noProgress)
        #expect(state.calls == 6)
        #expect(trace.diagnostics.modelRequests == 7)
        #expect(trace.diagnostics.events.filter { $0.kind == "progress_recovery" }.count == 1)
        #expect(trace.diagnostics.events.filter { $0.kind == "response" }.allSatisfy { $0.values["elapsed_ms"] != nil })
    }

    @Test func contextEstimateUpdatesWhileTheTaskIsStillRunning() async {
        let state = HarnessToolState()
        let fixture = HarnessFixture([.calls(["readPage"]), .calls(["readPage"]), .text("Done.")], state: state)
        var observations: [Int] = []
        state.output = { _ in
            #expect(fixture.log.latestTrace(forTab: fixture.tabID)?.state == .running)
            observations.append(fixture.log.usage(forTab: fixture.tabID).estimatedContextTokens)
            return String(repeating: "Fixture page content ", count: 100)
        }
        await fixture.run()
        #expect(observations.count == 2)
        #expect(observations.first ?? 0 > 0)
        #expect((observations.last ?? 0) > (observations.first ?? 0))
    }

    @Test func progressRestoresRecoveryForALaterIndependentStall() {
        var monitor = AgentProgressMonitor(policy: .interactive)
        for _ in 0..<2 {
            #expect(monitor.observe(name: "readPage", arguments: "a", output: "unchanged", failed: true) == .proceed)
        }
        #expect(monitor.observe(name: "readPage", arguments: "a", output: "unchanged", failed: true) == .recover)
        for index in 0..<3 {
            #expect(monitor.observe(name: "readPage", arguments: "a", output: "page \(index)", failed: false) == .proceed)
        }
        for _ in 0..<2 {
            #expect(monitor.observe(name: "typeOnPage", arguments: "b", output: "new failure", failed: true) == .proceed)
        }
        #expect(monitor.observe(name: "typeOnPage", arguments: "b", output: "new failure", failed: true) == .recover)
    }

    @Test func remoteWorkContinuesPastSixtyToolsWithoutACap() async throws {
        let fixture = HarnessFixture(Array(repeating: .calls(["typeOnPage"]), count: 60) + [.text("Finished all fields.")])
        await fixture.run()
        let trace = try #require(fixture.log.latestTrace(forTab: fixture.tabID))
        #expect(fixture.state.calls == 60)
        #expect(trace.state == .completed)
        #expect(fixture.reply.text == "Finished all fields.")
        #expect(trace.diagnostics.modelRequests == 61)
        #expect(trace.diagnostics.toolCalls == 60)
        #expect(trace.diagnostics.model == "gpt-5.6-luna")
        #expect(trace.diagnostics.reasoningEffort == "medium")
        #expect(trace.diagnostics.inputTokens == nil)
    }

    @Test func adapterProposalsAreExecutedExactlyOnceByTheHarness() async {
        let fixture = HarnessFixture([.calls(["readPage", "typeOnPage"]), .text("Done.")])
        await fixture.run()
        #expect(fixture.state.calls == 2)
        #expect(fixture.model.requests.count == 2)
        let history = fixture.model.transcripts.last.map(HarnessFixture.flattened) ?? ""
        #expect(history.contains("Observed state 1"))
        #expect(history.contains("Observed state 2"))
    }

    @Test func explicitLimitPausesWithSummaryAndCanResumeAfterReload() async throws {
        let fixture = HarnessFixture([.calls(["typeOnPage"])], policy: .init(maxModelRequests: 1))
        await fixture.run()
        let trace = try #require(fixture.log.latestTrace(forTab: fixture.tabID))
        #expect(trace.state == .paused)
        #expect(trace.stopReason == .requestLimit)
        #expect(trace.canContinue)
        #expect(trace.response.contains("earlier fields"))
        #expect(trace.response.contains("Continue"))
        let resumed = HarnessFixture([.text("Finished.")], database: fixture.database, tabID: fixture.tabID)
        await resumed.run(AgentCheckpoint.resumePrompt)
        #expect(resumed.state.calls == 0)
        #expect(resumed.model.transcripts.first.map(HarnessFixture.flattened)?.contains("Observed state 1") == true)
        #expect(resumed.reply.text == "Finished.")
    }

    @Test func repeatedUnchangedActionsRecoverThenPause() async throws {
        let state = HarnessToolState()
        state.output = { _ in "Same unchanged page" }
        let fixture = HarnessFixture(Array(repeating: .calls(["typeOnPage"]), count: 15), state: state)
        await fixture.run()
        let trace = try #require(fixture.log.latestTrace(forTab: fixture.tabID))
        #expect(trace.stopReason == .noProgress)
        #expect(state.calls == 6)
        #expect(trace.diagnostics.events.filter { $0.kind == "progress_recovery" }.count == 1)
        #expect(fixture.model.requests.contains { $0.contains("fresh controls") })
    }

    @Test func anIndividualToolFailureDoesNotEndTheTask() async throws {
        let state = HarnessToolState()
        state.output = { call in
            if call == 1 {
                throw HarnessFixtureFailure()
            }
            return "Validation corrected; moved to next page"
        }
        let fixture = HarnessFixture([.calls(["typeOnPage"]), .calls(["readPage"]), .text("Recovered.")], state: state)
        await fixture.run()
        let trace = try #require(fixture.log.latestTrace(forTab: fixture.tabID))
        #expect(trace.state == .completed)
        #expect(trace.diagnostics.failedToolCalls == 1)
        #expect(fixture.reply.text == "Recovered.")
        #expect(!trace.diagnostics.exported().contains("private@example.test"))
    }

    @Test func providerFailurePreservesCompletedActionsAndDoesNotLeakErrorText() async throws {
        let fixture = HarnessFixture([.calls(["typeOnPage"]), .failure(HarnessFixtureFailure())])
        await fixture.run()
        let trace = try #require(fixture.log.latestTrace(forTab: fixture.tabID))
        #expect(trace.state == .paused)
        #expect(trace.stopReason == .providerError)
        #expect(trace.checkpoint.map { HarnessFixture.flattened($0.transcript).contains("Observed state 1") } == true)
        #expect(!trace.response.contains("private@example.test"))
        #expect(!trace.diagnostics.exported().contains("ABC123"))
    }

    @Test func cancellationCheckpointsAnInFlightWriteWithoutReplayingIt() async throws {
        let state = HarnessToolState()
        state.output = { _ in
            let suspended = AsyncStream<Void> { _ in }
            for await _ in suspended { }
            try Task.checkCancellation()
            return "Should not arrive"
        }
        let fixture = HarnessFixture([.calls(["typeOnPage"])], state: state)
        let running = Task { await fixture.run() }
        defer { running.cancel() }
        try #require(await waitUntil { state.calls == 1 })
        running.cancel()
        _ = await running.value
        let trace = try #require(fixture.log.latestTrace(forTab: fixture.tabID))
        #expect(trace.stopReason == .interrupted)
        #expect(state.calls == 1)
        let resumed = HarnessFixture([.text("I checked the current page.")], database: fixture.database, tabID: fixture.tabID)
        await resumed.run(AgentCheckpoint.resumePrompt)
        #expect(resumed.state.calls == 0)
        #expect(resumed.model.transcripts.first.map(HarnessFixture.flattened)?.contains("Check the current page") == true)
    }

    @Test func twoEmptyAnswersPauseInsteadOfSpinning() async throws {
        let fixture = HarnessFixture([.text(""), .text("")])
        await fixture.run()
        #expect(fixture.model.requests.count == 2)
        #expect(fixture.log.latestTrace(forTab: fixture.tabID)?.state == .paused)
        #expect(fixture.reply.text?.contains("empty response") == true)
    }

    @Test func attachmentsReachTheModelOnceAndSurviveRestoringHistory() async {
        let fixture = HarnessFixture([.calls(["readPage"]), .text("Read.")])
        let file = AssistantAttachment(
            id: UUID(), name: "invoice.png", contentType: "public.png", data: Data([1]),
            text: "Fixture invoice 42", images: [.init(data: Data([1]), mimeType: "image/png")]
        )
        await fixture.run("Read this", attachments: [file])
        for transcript in fixture.model.transcripts {
            let count = transcript.reduce(0) { count, entry in
                guard case .prompt(let prompt) = entry else { return count }
                return count + prompt.segments.filter { if case .image = $0 { return true }; return false }.count
            }
            #expect(count == 1)
        }
        let resumed = HarnessFixture([.text("42")], database: fixture.database, tabID: fixture.tabID)
        await resumed.run("What was the total?")
        #expect(resumed.model.transcripts.first.map(HarnessFixture.flattened)?.contains("Fixture invoice 42") == true)
    }
}
