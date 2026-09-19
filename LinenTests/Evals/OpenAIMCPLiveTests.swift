// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import Testing

@testable import Linen

@MainActor
struct OpenAIMCPLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LINEN_OPENAI_LIVE_CONFIG"] != nil))
    func publicReadOnlyMCPApprovalRoundTrip() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["LINEN_OPENAI_LIVE_CONFIG"])
        let config = try OpenAIJSON.decode(Data(contentsOf: URL(fileURLWithPath: path)))
        guard config["mcp_only"] == true, config["live"] == true else { return }
        let model = config["model"].string ?? LLMSettings.model(for: ProviderCatalog.openAI)
        let destination = URL(fileURLWithPath: try #require(config["report_path"].string))
        let recorder = OpenAILiveRecorder(requestLimit: 3)
        var report: OpenAIJSON = [
            "mode": "live_mcp_acceptance", "status": "running", "model": .string(model),
            "source_sha256": config["source_sha256"], "synthetic_prompt": true, "competitive_score": false,
            "server": "https://mcp.deepwiki.com/mcp", "allowed_tool": "read_wiki_structure",
            "approval": "fixture_explicit_choice_for_public_read_only_request", "requests": [],
        ]
        func save() throws {
            report["requests"] = .array(recorder.snapshot)
            try report.data().write(to: destination, options: .atomic)
        }
        guard let key = ProcessInfo.processInfo.environment["LINEN_OPENAI_LIVE_KEY"] ?? CredentialStore.key(for: ProviderCatalog.openAI), !key.isEmpty else {
            report["status"] = "blocked_missing_credential"
            try save()
            return
        }
        try save()
        do {
            var settings = OpenAIResponseSettings()
            settings.mcpServers = [.init(label: "public_docs", destination: "https://mcp.deepwiki.com/mcp", allowedTools: ["read_wiki_structure"])]
            settings.additionalParameters = ["tool_choice": ["type": "mcp", "server_label": "public_docs", "name": "read_wiki_structure"]]
            let endpoint = URL(string: "https://api.openai.com/v1")!
            var client = OpenAIResponsesClient(endpoint: endpoint, apiKey: key, model: model, settings: settings,
                                               transport: OpenAILiveTransport(base: OpenAIHTTPTransport(baseURL: endpoint, apiKey: key), recorder: recorder))
            recorder.select("mcp_proposal")
            let first = try await client.respond(transcript: Transcript(entries: []),
                prompt: "Call read_wiki_structure with repoName exactly openai/openai-python. After approval, confirm only whether it returned a documentation structure.",
                images: [], state: client.restoring(nil), tools: [], maxTokens: 1_024, onText: { _ in })
            let pending = try #require(first.state.items.last { $0["type"] == "mcp_approval_request" })
            let arguments = try OpenAIJSON.decode(Data(try #require(pending["arguments"].string).utf8))
            guard pending["server_label"] == "public_docs", pending["name"] == "read_wiki_structure",
                  arguments.object?.count == 1, arguments["repoName"] == "openai/openai-python", first.calls.count == 1 else {
                throw OpenAILiveFailure.invariant
            }
            let approval = try OpenAIMCPApproval(pending, destination: "https://mcp.deepwiki.com/mcp")
            let questions = AgentQuestionModel()
            let ask = questions.present([.init(text: approval.question, options: [OpenAIMCPApproval.deny, OpenAIMCPApproval.approve])], inSpace: UUID())
            questions.answer(OpenAIMCPApproval.approve)
            let answer = await questions.result(for: ask)
            let output = Transcript.ToolOutput(id: approval.id, toolName: "askUser", segments: [.text(.init(content: answer))])
            var entries = Array(first.transcript)
            entries.append(.toolOutput(output))
            client.settings.additionalParameters = [:]
            recorder.select("mcp_approved_result")
            var submitted = try first.state.synchronizing(Transcript(entries: entries))
            let fresh = submitted.unsubmittedMCPApprovals
            submitted.recordMCPApprovalAttempts(fresh)
            guard submitted.mcpRequestItems(toolsEnabled: true).contains(where: {
                $0["type"] == "mcp_approval_response" && $0["approve"] == false
            }) else { throw OpenAILiveFailure.invariant }
            let second = try await OpenAIMCPExecutionScope.$freshApprovals.withValue(fresh) {
                try await client.respond(transcript: Transcript(entries: entries), prompt: "Continue from the approved public read-only tool result.",
                                         images: [], state: submitted, tools: [], maxTokens: 1_024, onText: { _ in })
            }
            let call = second.state.items.last { $0["type"] == "mcp_call" && $0["name"] == "read_wiki_structure" }
            guard second.calls.isEmpty, let call, call["error"] == .null, call["approval_request_id"].string == approval.id,
                  call["output"].string?.isEmpty == false, second.state.usage?.input != nil else { throw OpenAILiveFailure.invariant }
            guard !second.state.hasUnconfirmedMCPCall else { throw OpenAILiveFailure.invariant }
            client.settings.additionalParameters = ["tool_choice": "none"]
            recorder.select("mcp_resolved_history")
            let third = try await client.respond(transcript: second.transcript, prompt: "Reply ready without calling tools.",
                                                 images: [], state: second.state, tools: [], maxTokens: 128, onText: { _ in })
            guard third.calls.isEmpty, !third.text.isEmpty, recorder.snapshot.last?["output_types"].array?.allSatisfy({ ["message", "reasoning"].contains($0.string ?? "") }) == true else {
                throw OpenAILiveFailure.invariant
            }
            report["resolved_history_replayed_without_tool_execution"] = true
            report["approval_request_matched"] = true
            report["remote_call_completed"] = true
            report["status"] = "passed"
        } catch {
            report["status"] = "failed"
            report["error"] = .string(OpenAILiveRecorder.errorCode(error))
            Issue.record("Native MCP acceptance failed; see the sanitized report.")
        }
        try save()
    }
}
