// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import GRDB
import Testing

@testable import Linen

@MainActor
struct AgentDiagnosticPrivacyTests {
    @Test func noArbitraryTextCanEnterDiagnosticEvents() throws {
        let secret = "person@example.test +44 7000 123456 tax-id-123 https://private.test/account"
        let event = AgentEvaluationEvent(kind: "tool_completed", values: [
            "name": secret, "arguments": secret, "output": secret, "prompt": secret,
            "error": secret, "id": secret, "reason": secret, "status": secret,
            "elapsed_ms": secret, "count": "12",
        ])
        #expect(event.values == ["name": "custom_tool", "count": "12"])
        let encoded = try JSONEncoder().encode(event)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("person@example.test"))
        let decoded = try JSONDecoder().decode(AgentEvaluationEvent.self, from: Data("""
            {"kind":"email@example.test","values":{"output":"private","status":"done-secret"}}
            """.utf8))
        #expect(decoded.kind == "unknown")
        #expect(decoded.values.isEmpty)
    }

    @Test func providerFailureKeepsOnlySafeCategoryAndStatus() {
        let event = AgentEvaluationEvent(kind: "provider_failure", values: [
            "failure_kind": "streamInterrupted", "http_status": "502", "api_code": "server_error",
            "error": "private@example.test",
        ])
        #expect(event.kind == "provider_failure")
        #expect(event.values == ["failure_kind": "streamInterrupted", "http_status": "502", "api_code": "server_error"])
        #expect(AgentEvaluationEvent(kind: "provider_failure", values: ["api_code": "private@example.test"]).values.isEmpty)
    }

    @Test(arguments: ["previous_response_not_found", "websocket_connection_limit_reached", "insufficient_quota"])
    func providerFailureRetainsKnownActionableCodes(code: String) {
        let event = AgentEvaluationEvent(kind: "provider_failure", values: ["api_code": code, "http_status": "400"])
        #expect(event.values == ["api_code": code, "http_status": "400"])
    }

    @Test func diagnosticExportDropsCustomModelAndEffortIdentifiers() {
        var diagnostics = AgentRunDiagnostics()
        diagnostics.model = "customer-private-finetune-123"
        diagnostics.reasoningEffort = "private-user-name"
        let exported = diagnostics.exported()
        #expect(!exported.contains("private"))
        #expect(exported.contains("custom_model"))
        #expect(!exported.contains("inputTokens"))
    }

    @Test func activityIsMechanicalWhilePrivateAnswersRemainResumable() async throws {
        let state = HarnessToolState()
        state.output = { _ in "Q: Email? A: private@example.test" }
        let fixture = HarnessFixture([.calls(["askUser"]), .text("Saved.")], state: state)
        await fixture.run("My private conversation")
        let id = try #require(fixture.log.latestTrace(forTab: fixture.tabID)?.id)
        let step = fixture.log.beginTask("Another private question", tabID: fixture.tabID)
        let action = fixture.log.beginTool(taskID: step, name: "typeOnPage", title: "private@example.test", detail: "secret")
        fixture.log.completeTool(taskID: step, stepID: action, detail: "secret", links: [.init(title: "secret", url: URL(string: "https://private.test")!)])
        fixture.log.saveBlocking()
        try await fixture.database.writer.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT title, toolName, detail, links FROM agentStep")
            for row in rows {
                let detail: String? = row["detail"]
                let links: String = row["links"]
                let title: String = row["title"]
                #expect(detail == nil)
                #expect(links == "[]")
                #expect(!title.contains("private"))
            }
        }
        let restored = ConversationLog(database: fixture.database)
        #expect(restored.traces.first(where: { $0.id == id })?.checkpoint?.userAnswers == ["Q: Email? A: private@example.test"])
        #expect(!restored.traces.first(where: { $0.id == id })!.diagnostics.exported().contains("private"))
        restored.clearAll()
        let remaining = try await fixture.database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM agentConversationMemory")
        }
        #expect(remaining == 0)
    }
}
