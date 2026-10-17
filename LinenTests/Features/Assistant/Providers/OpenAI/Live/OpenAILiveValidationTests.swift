// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import Testing

@testable import Linen

@MainActor
struct OpenAILiveValidationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LINEN_OPENAI_LIVE_CONFIG"] != nil))
    func liveValidation() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["LINEN_OPENAI_LIVE_CONFIG"])
        let config = try OpenAIJSON.decode(Data(contentsOf: URL(fileURLWithPath: path)))
        let reportURL = URL(fileURLWithPath: try #require(config["report_path"].string))
        let model = config["model"].string ?? LLMSettings.model(for: ProviderCatalog.openAI)
        let key = ProcessInfo.processInfo.environment["LINEN_OPENAI_LIVE_KEY"] ?? CredentialStore.key(for: ProviderCatalog.openAI)
        let hostedOnly = config["hosted_only"].bool == true
        let requestLimit = hostedOnly ? 10 : (config["hosted_tools"].bool == true ? 32 : 20)
        let recorder = OpenAILiveRecorder(requestLimit: requestLimit)
        var report: OpenAIJSON = [
            "mode": config["live"].bool == true ? "live_acceptance" : "credential_preflight",
            "model": .string(model), "reasoning_effort": "low", "store": false,
            "max_requests": .integer(Int64(requestLimit)), "hosted_only": .bool(hostedOnly), "max_output_tokens_per_response": 2_048,
            "synthetic_prompts": true, "synthetic_usage": false, "competitive_score": false,
            "credential_available": .bool(key?.isEmpty == false), "status": "ready",
            "source_sha256": config["source_sha256"], "checks": [], "requests": [],
        ]
        func save() throws {
            report["requests"] = .array(recorder.snapshot)
            try report.data().write(to: reportURL, options: .atomic)
        }
        guard let key, !key.isEmpty else {
            report["status"] = "blocked_missing_credential"
            try save()
            return
        }
        guard config["live"].bool == true else {
            try save()
            return
        }
        let endpoint = URL(string: "https://api.openai.com/v1")!
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = 90
        sessionConfig.timeoutIntervalForResource = 240
        let session = URLSession(configuration: sessionConfig)
        defer { session.invalidateAndCancel() }
        let transport = OpenAILiveTransport(base: OpenAIHTTPTransport(baseURL: endpoint, apiKey: key, session: session), recorder: recorder)
        let client = OpenAIResponsesClient(endpoint: endpoint, apiKey: key, model: model, transport: transport)
        var checks: [OpenAIJSON] = []
        func check(_ name: String, _ body: () async throws -> Void) async throws {
            recorder.select(name)
            report["current_check"] = .string(name)
            report["status"] = "running"
            try save()
            do {
                try await body()
                checks.append(["name": .string(name), "passed": true])
            } catch {
                checks.append(["name": .string(name), "passed": false, "error": .string(OpenAILiveRecorder.errorCode(error))])
                report["checks"] = .array(checks)
                report["status"] = "failed"
                try save()
                throw error
            }
            report["checks"] = .array(checks)
            try save()
        }
        do {
            if !hostedOnly {
                try await check("model_access") {
                    let result = try await client.api.request(["models", model], method: "GET")
                    try require(result["id"].string == model)
                }
                try await check("http_streaming") {
                    var text = ""
                    let step = try await client.respond(transcript: Transcript(), prompt: "Reply with exactly LINEN_OK.", images: [],
                        state: client.restoring(nil), tools: [], maxTokens: 2_048, onText: { text = $0 })
                    try require(step.text.contains("LINEN_OK") && !text.isEmpty && step.firstTextMilliseconds != nil)
                    try require(step.state.usage?.input != nil && step.state.usage?.output != nil)
                }
                try await check("utility_text_and_structured_array") {
                    let utility = OpenAIUtilityModel(client: client, maxTokens: 2_048)
                    let plain = LanguageModelSession(model: utility)
                    let answer = try await plain.respond(to: "Reply with exactly LINEN_OK.")
                    try require(answer.content.contains("LINEN_OK"))
                    let structured = LanguageModelSession(model: utility)
                    let array = try await structured.respond(to: "Return exactly these two strings in order: alpha, beta.", generating: [String].self)
                    try require(array.content == ["alpha", "beta"])
                }
                try await check("function_state_and_compaction") {
                    try await toolAndCompaction(client)
                }
                try await check("websocket_continuation_and_new_connection") {
                    try await sockets(endpoint: endpoint, key: key, model: model, recorder: recorder)
                }
            }
            if config["hosted_tools"].bool == true {
                try await check("hosted_web_search") {
                    report["web_search"] = try await OpenAIHostedLiveChecks.webSearch(client)
                }
                try await check("hosted_code_interpreter") {
                    report["code_interpreter"] = try await OpenAIHostedLiveChecks.codeInterpreter(client)
                }
                try await check("hosted_image_generation") {
                    report["image_generation"] = try await OpenAIHostedLiveChecks.imageGeneration(client)
                }
            }
            report["status"] = "passed"
            report["current_check"] = .null
            try save()
        } catch {
            Issue.record("Live OpenAI validation failed: \(OpenAILiveRecorder.errorCode(error)). See the sanitized report.")
        }
    }

    private func toolAndCompaction(_ client: OpenAIResponsesClient) async throws {
        var forced = client
        forced.settings.additionalParameters = ["tool_choice": ["type": "function", "name": "readPage"]]
        let state = HarnessToolState()
        let tool = HarnessTool(name: "readPage", state: state)
        let tools: [any Tool] = [tool]
        let first = try await forced.respond(transcript: Transcript(), prompt: "Call readPage with value fixture.", images: [],
            state: forced.restoring(nil), tools: tools, maxTokens: 2_048, onText: { _ in })
        try require(first.calls.count == 1 && state.calls == 0)
        let call = first.calls[0]
        try require(call.toolName == "readPage")
        let arguments = try HarnessTool.Arguments(call.arguments)
        try require(arguments.value == "fixture")
        let value = try await tool.call(arguments: arguments)
        let entries = Array(first.transcript) + [
            .toolOutput(.init(id: call.id, toolName: call.toolName, segments: [.text(.init(content: value))])),
        ]
        let second = try await client.respond(transcript: Transcript(entries: entries),
            prompt: "Report the tool result. Remember the marker PINEAPPLE_42 for the next turn.", images: [], state: first.state,
            tools: [], maxTokens: 2_048, onText: { _ in })
        try require(state.calls == 1 && second.text.contains("Observed state 1"))
        let restored = try JSONDecoder().decode(OpenAIConversationState.self, from: JSONEncoder().encode(second.state))
        let compacted = try await client.compact(state: client.restoring(restored), instructions: "Preserve the marker for recall.")
        try require(!compacted.items.isEmpty)
        let after = try await client.respond(transcript: second.transcript, prompt: "What exact marker were you asked to remember?",
            images: [], state: compacted, tools: [], maxTokens: 2_048, onText: { _ in })
        try require(after.text.contains("PINEAPPLE_42"))
    }

    private func sockets(endpoint: URL, key: String, model: String, recorder: OpenAILiveRecorder) async throws {
        func makeClient() -> OpenAIResponsesClient {
            let socket = OpenAIWebSocketTransport(http: OpenAIHTTPTransport(baseURL: endpoint, apiKey: key))
            return .init(endpoint: endpoint, apiKey: key, model: model, transport: OpenAILiveTransport(base: socket, recorder: recorder))
        }
        let client = makeClient()
        let first = try await client.respond(transcript: Transcript(), prompt: "Remember ORCHID_73. Reply OK.", images: [],
            state: client.restoring(nil), tools: [], maxTokens: 2_048, onText: { _ in })
        let second = try await client.respond(transcript: first.transcript, prompt: "What exact marker did I give you?", images: [],
            state: first.state, tools: [], maxTokens: 2_048, onText: { _ in })
        try require(second.text.contains("ORCHID_73"))
        let fresh = makeClient()
        let third = try await fresh.respond(transcript: second.transcript, prompt: "Repeat the exact marker once more.", images: [],
            state: fresh.restoring(second.state), tools: [], maxTokens: 2_048, onText: { _ in })
        try require(third.text.contains("ORCHID_73"))
    }

    private func require(_ condition: Bool) throws {
        guard condition else { throw OpenAILiveFailure.invariant }
    }
}
