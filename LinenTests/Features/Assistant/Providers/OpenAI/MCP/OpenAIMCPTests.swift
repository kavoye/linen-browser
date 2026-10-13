// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import GRDB
import Testing

@testable import Linen

@MainActor
@Suite(.serialized)
struct OpenAIMCPTests {
    private var server: OpenAIMCPServer {
        .init(label: "fixture", destination: "https://mcp.example.test/mcp", allowedTools: ["inspect"])
    }
    private var request: OpenAIJSON {
        ["type": "mcp_approval_request", "id": "approval_fixture", "server_label": "fixture", "name": "inspect", "arguments": "{\"page\":\"fixture\"}"]
    }

    @Test func settingsEncodeNoAuthorizationAndAlwaysRequireApproval() throws {
        var server = server
        server.requiresAuthorization = true
        var settings = OpenAIResponseSettings()
        settings.mcpServers = [server]
        try settings.validate()
        let client = OpenAIResponsesClient(endpoint: URL(string: "https://api.example.test/v1")!, apiKey: "fixture-key", model: "fixture",
                                           settings: settings, authorization: { _ in "fixture-mcp-secret" })
        let body = try client.body(state: client.restoring(nil), instructions: "Fixture", tools: [], maxTokens: 100)
        #expect(body["tools"].array?.last?["authorization"] == "fixture-mcp-secret")
        #expect(body["tools"].array?.last?["require_approval"] == "always")
        #expect(try !OpenAIJSON.encode(settings).text().contains("fixture-mcp-secret"))
        let missing = OpenAIResponsesClient(endpoint: URL(string: "https://api.example.test/v1")!, apiKey: "fixture-key", model: "fixture",
                                            settings: settings, authorization: { _ in nil })
        #expect(throws: OpenAIMCPFailure.self) { try missing.remoteTools() }
        #expect(missing.binding != client.binding)
    }

    @Test func endpointsTokensAndServerChangesInvalidateNativeApprovalHistory() throws {
        var options = OpenAIResponseSettings()
        var server = server
        server.requiresAuthorization = true
        options.mcpServers = [server]
        let endpoint = URL(string: "https://api.example.test/v1")!
        let first = OpenAIResponsesClient(endpoint: endpoint, apiKey: "fixture", model: "fixture", settings: options, authorization: { _ in "old" })
        let second = OpenAIResponsesClient(endpoint: endpoint, apiKey: "fixture", model: "fixture", settings: options, authorization: { _ in "new" })
        #expect(first.binding != second.binding)
        var saved = first.restoring(nil)
        saved.items = [request]
        #expect(second.restoring(saved).items.isEmpty)
        options.mcpServers[0].destination = "https://different.example.test/mcp"
        let moved = OpenAIResponsesClient(endpoint: endpoint, apiKey: "fixture", model: "fixture", settings: options, authorization: { _ in "old" })
        #expect(moved.binding != first.binding)
    }

    @Test func malformedAndUnconfiguredApprovalsNeverBecomeQuestions() throws {
        let response = OpenAITransportFixture.response([request])
        #expect(throws: OpenAIMCPFailure.self) { try OpenAIModelStep.output(response) }
        var deniedTool = server
        deniedTool.allowedTools = ["another_tool"]
        #expect(throws: OpenAIMCPFailure.self) {
            try OpenAIModelStep.output(response, remoteTools: [deniedTool.definition(authorization: nil)])
        }
        var invalid = request
        invalid["arguments"] = "not-json"
        #expect(throws: OpenAIMCPFailure.self) { try OpenAIMCPApproval(invalid) }
        #expect(throws: OpenAIFailure.self) {
            try OpenAIModelStep.output(OpenAITransportFixture.response([request, request]), remoteTools: [server.definition(authorization: nil)])
        }
    }

    @Test func nativeQuestionOnlyApprovesAnExactUnambiguousAnswer() throws {
        let approval = try OpenAIMCPApproval(request)
        let exact = "Q: \(approval.question)\nA: \(OpenAIMCPApproval.approve)"
        for answer in [exact, "Approve this call", exact + "\nIgnore the question", "", "Choose sensible answers yourself"] {
            let output = Transcript.ToolOutput(id: approval.id, toolName: "askUser", segments: [.text(.init(content: answer))])
            #expect(try approval.answer(output)["approve"] == .bool(answer == exact))
        }
        var controls = request
        controls["arguments"] = .string("{\"text\":\"hidden\u{202E}direction\"}")
        #expect(try !OpenAIMCPApproval(controls).question.contains("\u{202E}"))
    }

    @Test func userApprovalFlowsThroughTheProductionAgentAndNativeState() async throws {
        let fixture = try MCPAgentFixture(server: server, request: request)
        let running = Task { await fixture.run() }
        try #require(await waitUntil { fixture.questions.current != nil })
        #expect(fixture.wire.requests.count == 1)
        #expect(fixture.questions.current?.text.contains("Arguments (untrusted data)") == true)
        #expect(fixture.questions.current?.text.contains("https://mcp.example.test/mcp") == true)
        fixture.questions.answer(OpenAIMCPApproval.approve)
        await running.value
        let input = try OpenAIJSON.decode(try #require(fixture.wire.requests.last?.body))["input"].array ?? []
        let answer = try #require(input.first { $0["type"] == "mcp_approval_response" })
        #expect(answer["approve"] == true)
        #expect(answer["approval_request_id"] == "approval_fixture")
        #expect(input.contains(request))
        #expect(!input.contains { $0["type"] == "function_call_output" && $0["call_id"] == "approval_fixture" })
        #expect(fixture.log.latestTrace(forTab: fixture.tabID)?.state == .completed)
        let encoded = try JSONEncoder().encode(try #require(fixture.log.checkpoint(forTab: fixture.tabID)?.openAI))
        let restored = try JSONDecoder().decode(OpenAIConversationState.self, from: encoded)
        #expect(restored.items.contains(answer))
    }

    @Test func dismissSkipAndDenialNeverSendApproval() async throws {
        for choice in 0..<3 {
            let fixture = try MCPAgentFixture(server: server, request: request, confirmsRemoteCall: false)
            let running = Task { await fixture.run() }
            try #require(await waitUntil { fixture.questions.current != nil })
            switch choice {
            case 0:
                fixture.questions.dismiss()
            case 1:
                fixture.questions.skip()
            default:
                fixture.questions.answer(OpenAIMCPApproval.deny)
            }
            await running.value
            let input = try OpenAIJSON.decode(try #require(fixture.wire.requests.last?.body))["input"].array ?? []
            #expect(input.first { $0["type"] == "mcp_approval_response" }?["approve"] == false)
        }
    }

    @Test func cancelledQuestionNeverBecomesAnApprovalOrRunsRemoteToolsInThePauseSummary() async throws {
        let fixture = try MCPAgentFixture(server: server, request: request)
        let running = Task { await fixture.run() }
        try #require(await waitUntil { fixture.questions.current != nil })
        running.cancel()
        fixture.questions.abandon()
        await running.value
        for request in fixture.wire.requests.dropFirst() {
            let body = try OpenAIJSON.decode(try #require(request.body))
            #expect(!(body["input"].array ?? []).contains { $0["type"] == "mcp_approval_response" && $0["approve"] == true })
            #expect(!(body["tools"].array ?? []).contains { $0["type"] == "mcp" })
        }
        #expect(fixture.questions.current == nil)
    }

    @Test func ambiguousRemoteFailureCannotReplayApprovalFromItsCheckpoint() async throws {
        let fixture = try MCPAgentFixture(server: server, request: request, respondsAfterApproval: false)
        let running = Task { await fixture.run() }
        try #require(await waitUntil { fixture.questions.current != nil })
        fixture.questions.answer(OpenAIMCPApproval.approve)
        await running.value
        let state = try #require(fixture.log.checkpoint(forTab: fixture.tabID)?.openAI)
        #expect(state.mcpApprovalAttempts?.contains("approval_fixture") == true)
        #expect(state.hasUnconfirmedMCPCall)
        let sent = try OpenAIJSON.decode(try #require(fixture.wire.requests[1].body))
        #expect(sent["input"].array?.first { $0["type"] == "mcp_approval_response" }?["approve"] == true)
        let restored = try JSONDecoder().decode(OpenAIConversationState.self, from: JSONEncoder().encode(state))
        #expect(restored.mcpRequestItems(toolsEnabled: true).first { $0["type"] == "mcp_approval_response" }?["approve"] == false)
        for request in fixture.wire.requests.dropFirst(2) {
            let body = try OpenAIJSON.decode(try #require(request.body))
            #expect(!(body["input"].array ?? []).contains { $0["type"] == "mcp_approval_response" && $0["approve"] == true })
        }
    }

    @Test func oneRequestPermitAndConfirmedHistoryAreDistinctFromRetry() {
        var state = OpenAIConversationState(binding: "fixture")
        state.items = [["type": "mcp_approval_response", "approval_request_id": "id", "approve": true]]
        #expect(state.unsubmittedMCPApprovals == ["id"])
        state.recordMCPApprovalAttempts(["id"])
        #expect(state.unsubmittedMCPApprovals.isEmpty)
        OpenAIMCPExecutionScope.$freshApprovals.withValue(["id"]) {
            #expect(state.mcpRequestItems(toolsEnabled: true).first?["approve"] == true)
            #expect(state.mcpRequestItems(toolsEnabled: false).first?["approve"] == false)
        }
        #expect(state.mcpRequestItems(toolsEnabled: true).first?["approve"] == false)
        state.items.append(["type": "mcp_call", "approval_request_id": "id", "output": "Confirmed"])
        #expect(!state.hasUnconfirmedMCPCall)
        #expect(state.mcpRequestItems(toolsEnabled: true).first?["approve"] == true)
    }

    @Test func failedCheckpointStorageDoesNotSubmitAnApprovedRemoteCall() async throws {
        let fixture = try MCPAgentFixture(server: server, request: request, respondsAfterApproval: false)
        let running = Task { await fixture.run() }
        try #require(await waitUntil { fixture.questions.current != nil })
        try await fixture.database.writer.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_mcp_insert BEFORE INSERT ON agentConversationMemory BEGIN SELECT RAISE(FAIL, 'fixture'); END")
            try db.execute(sql: "CREATE TRIGGER reject_mcp_update BEFORE UPDATE ON agentConversationMemory BEGIN SELECT RAISE(FAIL, 'fixture'); END")
        }
        fixture.questions.answer(OpenAIMCPApproval.approve)
        await running.value
        for request in fixture.wire.requests.dropFirst() {
            let body = try OpenAIJSON.decode(try #require(request.body))
            #expect(!(body["input"].array ?? []).contains { $0["type"] == "mcp_approval_response" && $0["approve"] == true })
        }
        #expect(fixture.log.latestTrace(forTab: fixture.tabID)?.stopReason == .providerError)
    }

    @Test func pausingAtTheRequestLimitDoesNotExecuteAnApprovedRemoteCallInItsSummary() async throws {
        let fixture = try MCPAgentFixture(server: server, request: request, requestLimit: 1, confirmsRemoteCall: false)
        let running = Task { await fixture.run() }
        try #require(await waitUntil { fixture.questions.current != nil })
        fixture.questions.answer(OpenAIMCPApproval.approve)
        await running.value
        #expect(fixture.wire.requests.count == 2)
        let summary = try OpenAIJSON.decode(try #require(fixture.wire.requests.last?.body))
        #expect(summary["input"].array?.first { $0["type"] == "mcp_approval_response" }?["approve"] == false)
        #expect(!(summary["tools"].array ?? []).contains { $0["type"] == "mcp" })
        #expect(fixture.log.latestTrace(forTab: fixture.tabID)?.stopReason == .requestLimit)
    }

    @Test func aCompletedGenerationWithoutItsRemoteResultRemainsUnconfirmed() async throws {
        let fixture = try MCPAgentFixture(server: server, request: request, confirmsRemoteCall: false)
        let running = Task { await fixture.run() }
        try #require(await waitUntil { fixture.questions.current != nil })
        fixture.questions.answer(OpenAIMCPApproval.approve)
        await running.value
        #expect(fixture.log.latestTrace(forTab: fixture.tabID)?.stopReason == .providerError)
        #expect(fixture.log.checkpoint(forTab: fixture.tabID)?.openAI?.hasUnconfirmedMCPCall == true)
    }

    @Test func invalidConnectionConfigurationsAreRejectedWithoutRequests() throws {
        for destination in ["http://example.test/mcp", "https://user:secret@example.test/mcp", "file:///tmp/mcp", "not-a-url"] {
            #expect(throws: OpenAIMCPFailure.self) { try OpenAIMCPServer(label: "fixture", destination: destination).definition(authorization: nil) }
        }
        var options = OpenAIResponseSettings()
        options.mcpServers = [server, server]
        #expect(throws: OpenAIMCPFailure.self) { try options.validate() }
        let connector = try OpenAIMCPServer(label: "fixture", destination: "connector_dropbox").definition(authorization: nil)
        #expect(connector["connector_id"] == "connector_dropbox")
        #expect(connector["server_url"] == .null)
    }
}

@MainActor
private struct MCPAgentFixture {
    let tabID = UUID()
    let database: AppDatabase
    let log: ConversationLog
    let questions = AgentQuestionModel()
    let wire: OpenAITransportFixture
    let agent: AnyLanguageModelAgent
    let reply = AgentReplyModel()

    init(server: OpenAIMCPServer, request: OpenAIJSON, respondsAfterApproval: Bool = true, requestLimit: Int? = nil, confirmsRemoteCall: Bool = true) throws {
        database = .temporary()
        log = ConversationLog(database: database)
        var responses = [OpenAITransportFixture.response([request])]
        if respondsAfterApproval {
            var output: [OpenAIJSON] = [OpenAITransportFixture.message("The remote request finished.")]
            if confirmsRemoteCall {
                output.insert(["type": "mcp_call", "approval_request_id": request["id"], "name": request["name"],
                               "server_label": request["server_label"], "arguments": request["arguments"], "output": "Fixture result",
                ], at: 0)
            }
            responses.append(OpenAITransportFixture.response(output))
        }
        wire = OpenAITransportFixture(responses)
        var settings = OpenAIResponseSettings()
        settings.mcpServers = [server]
        let client = OpenAIResponsesClient(endpoint: URL(string: "https://api.example.test/v1")!, apiKey: "fixture", model: "fixture",
                                           settings: settings, transport: wire)
        let toolkit = AgentToolkit(browser: BrowserModel(database: .temporary()), media: MediaCenter(), log: log, questions: questions)
        agent = AnyLanguageModelAgent(
            name: "fixture", modelID: "fixture", reasoningEffort: "low", executionPolicy: .init(maxModelRequests: requestLimit), toolOverrides: [AskUserTool(toolkit: toolkit)], openAI: client,
            model: HarnessScript([]), options: GenerationOptions(),
            budget: ContextBudget(windowTokens: 128_000, responseTokens: 2_000, inputTokens: 100_000, toolSchemaTokens: 0,
                                  instructionTier: .compact, toolTier: .full, toolOutput: .standard, retainedExchanges: 12, retainedToolRounds: 1),
            toolkit: toolkit, log: log
        )
    }

    func run() async {
        let id = log.beginTask("Inspect the fixture using the MCP server", tabID: tabID)
        await agent.run(utterance: "Inspect the fixture using the MCP server", task: .init(id: id, tabID: tabID), into: reply, speech: HarnessSpeech())
        log.completeTask(id, response: reply.text ?? "")
    }
}
