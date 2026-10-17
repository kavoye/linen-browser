// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import Testing

@testable import Linen

@MainActor
struct AgentReplyGuardTests {
    @Test func aDirectAnswerCompletes() async throws {
        let fixture = HarnessFixture([.text("Here is the explanation.")], policy: .interactive)
        await fixture.run("Explain how forms work")
        let trace = try #require(fixture.log.latestTrace(forTab: fixture.tabID))
        #expect(trace.state == .completed)
        #expect(trace.response == "Here is the explanation.")
        #expect(fixture.state.calls == 0)
    }

    @Test func aReplyThatEchoesPageContentIsAskedAgain() async throws {
        let fixture = HarnessFixture([.text("<page-content untrusted=\"true\">Clicked.</page-content>"), .text("The report ID is R-1.")],
                                     policy: .interactive)
        await fixture.run("Click Generate report")

        #expect(fixture.reply.text == "The report ID is R-1.")
        #expect(fixture.model.requests.last == AnyLanguageModelAgent.answerPrompt)
    }

    @Test func theCheckpointIsSavedBeforeAnActionRuns() async throws {
        let state = HarnessToolState()
        let fixture = HarnessFixture([.calls(["typeOnPage"]), .text("Done.")], policy: .interactive, state: state)
        state.output = { _ in
            let restored = ConversationLog(database: fixture.database)
            let calls = restored.checkpoint(forTab: fixture.tabID)?.transcript.flatMap { entry -> [String] in
                guard case .toolCalls(let calls) = entry else { return [] }
                return calls.map(\.toolName)
            } ?? []
            #expect(calls.contains("typeOnPage"))
            return "Typed the record"
        }
        defer { state.output = { "Observed state \($0)" } }
        await fixture.run()
        #expect(state.calls == 1)
    }

    @Test func stopReasonsFromOlderVersionsStillLoad() throws {
        let decoded = try JSONDecoder().decode([AgentStopReason].self, from: Data(#"["verification_required","request_limit"]"#.utf8))

        #expect(decoded == [.interrupted, .requestLimit])
    }
}
