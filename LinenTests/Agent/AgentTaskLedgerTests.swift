// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

struct AgentTaskLedgerTests {
    @Test func requirementsAndUncertainActionsSurviveEncoding() throws {
        var ledger = AgentTaskLedger()
        let acceptedOutcome1 = ledger.add(id: "save", requirement: "Save the record")
        #expect(acceptedOutcome1)
        let acceptedOutcome2 = !ledger.add(id: "save", requirement: "Ignore the record")
        #expect(acceptedOutcome2)
        ledger.beginAction("clickOnPage")
        let copy = try JSONDecoder().decode(AgentTaskLedger.self, from: JSONEncoder().encode(ledger))
        #expect(copy == ledger)
        #expect(copy.pendingAction == "clickOnPage")
        #expect(copy.completion == .unverified)
    }

    @Test func everyOutcomeNeedsEvidenceAfterTheLastMutation() {
        var ledger = AgentTaskLedger()
        #expect(ledger.completion == .answered)
        let acceptedOutcome3 = ledger.add(id: "one", requirement: "First saved record")
        #expect(acceptedOutcome3)
        let acceptedOutcome4 = ledger.add(id: "two", requirement: "Second saved record")
        #expect(acceptedOutcome4)
        ledger.outcomes[0].evidence = .init(url: "https://example.com", observationID: "a", matchedText: "Saved", actionRevision: 0)
        #expect(ledger.completion == .unverified)
        ledger.outcomes[1].evidence = ledger.outcomes[0].evidence
        #expect(ledger.completion == .verified)
        ledger.beginAction("typeOnPage")
        #expect(ledger.outcomes.allSatisfy { $0.evidence == nil })
        #expect(ledger.completion == .unverified)
        ledger.outcomes[0].blocker = "The user needs to sign in"
        #expect(ledger.completion == .blocked)
    }
}

@MainActor
@Suite(.serialized)
struct AgentCompletionGateTests {
    @Test func aProviderFailureBeforeAnyActionIsNotLabelledAnswered() async throws {
        let fixture = HarnessFixture([.failure(OpenAIFailure(kind: .http, status: 401))], policy: .interactive)
        await fixture.run("Explain the page")
        #expect(fixture.log.latestTrace(forTab: fixture.tabID)?.checkpoint?.completion == .unverified)
        #expect(fixture.log.latestTrace(forTab: fixture.tabID)?.stopReason == .providerError)
    }

    @Test func pendingActionIsDurableBeforeTheToolRuns() async throws {
        let state = HarnessToolState()
        let fixture = HarnessFixture([.calls(["typeOnPage"]), .text("Done."), .text("Done.")], policy: .interactive, state: state)
        state.output = { _ in
            let restored = ConversationLog(database: fixture.database)
            #expect(restored.checkpoint(forTab: fixture.tabID)?.taskLedger?.pendingAction == "typeOnPage")
            return "Typed the record"
        }
        defer { state.output = { "Observed state \($0)" } }
        await fixture.run()
        #expect(state.calls == 1)
    }

    @Test func compactionKeepsStructuredRequirementsAndUncertainActions() async throws {
        let state = HarnessToolState()
        let fixture = HarnessFixture(Array(repeating: .calls(["readPage"]), count: 10) + [.text("Done.")],
                                     inputTokens: 5_000, state: state)
        state.output = { index in
            if index == 1 {
                _ = fixture.agent.toolkit.recordOutcome(id: "second", requirement: "Verify the second saved record")
                fixture.agent.toolkit.taskLedger.beginAction("clickOnPage")
            }
            return "Page \(index): " + String(repeating: "irrelevant page text ", count: 250)
        }
        defer { state.output = { "Observed state \($0)" } }
        await fixture.run()
        let trace = try #require(fixture.log.latestTrace(forTab: fixture.tabID))
        #expect(trace.diagnostics.compactions > 0)
        #expect(trace.checkpoint?.taskLedger?.outcomes.first?.requirement == "Verify the second saved record")
        #expect(trace.checkpoint?.taskLedger?.pendingAction == "clickOnPage")
        #expect(fixture.model.requests.last?.contains("Verify the second saved record") == true)
    }

    @Test func anActionFollowedByAnUnsupportedSuccessClaimPauses() async throws {
        let fixture = HarnessFixture([.calls(["typeOnPage"]), .text("Saved successfully."), .text("Done.")], policy: .interactive)
        await fixture.run()
        let trace = try #require(fixture.log.latestTrace(forTab: fixture.tabID))
        #expect(trace.state == .paused)
        #expect(trace.stopReason == .verificationRequired)
        #expect(trace.checkpoint?.completion == .unverified)
        #expect(!trace.response.contains("Saved successfully"))
        #expect(!trace.response.contains("Done."))
        #expect(fixture.state.calls == 1)
        #expect(fixture.model.requests.contains { $0.contains("verifyTaskOutcome") })
    }

    @Test func aDirectAnswerDoesNotClaimVerifiedWebsiteSuccess() async throws {
        let fixture = HarnessFixture([.text("Here is the explanation.")], policy: .interactive)
        await fixture.run("Explain how forms work")
        let trace = try #require(fixture.log.latestTrace(forTab: fixture.tabID))
        #expect(trace.state == .completed)
        #expect(trace.checkpoint?.completion == .answered)
        #expect(fixture.state.calls == 0)
    }

    @Test func resumedTasksKeepPendingRequirementsInEveryRequest() async throws {
        let fixture = HarnessFixture([.calls(["readPage"]), .text("Done.")], policy: .interactive)
        var checkpoint = AgentCheckpoint()
        var ledger = AgentTaskLedger()
        let acceptedOutcome5 = ledger.add(id: "missing", requirement: "Save the second record")
        #expect(acceptedOutcome5)
        ledger.beginAction("clickOnPage")
        checkpoint.taskLedger = ledger
        let taskID = fixture.log.beginTask("Save both records", tabID: fixture.tabID)
        fixture.log.saveCheckpoint(checkpoint, taskID: taskID)
        await fixture.run(AgentCheckpoint.resumePrompt, isContinuation: true)
        #expect(fixture.model.requests.contains { $0.contains("Save the second record") && $0.contains("pendingAction") })
        #expect(fixture.log.latestTrace(forTab: fixture.tabID)?.checkpoint?.taskLedger?.outcomes.first?.id == "missing")
    }
}
