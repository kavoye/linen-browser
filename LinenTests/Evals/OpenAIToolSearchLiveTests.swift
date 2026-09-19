// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import Testing

@testable import Linen

@MainActor
struct OpenAIToolSearchLiveTests {
    private struct Scenario {
        let id: String
        let prompt: String
        let tool: String
        let result: String
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LINEN_OPENAI_LIVE_CONFIG"] != nil))
    func pairedBrowserToolDiscovery() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["LINEN_OPENAI_LIVE_CONFIG"])
        let config = try OpenAIJSON.decode(Data(contentsOf: URL(fileURLWithPath: path)))
        guard config["tool_search_only"] == true, config["live"] == true else { return }
        let model = config["model"].string ?? LLMSettings.model(for: ProviderCatalog.openAI)
        let reportURL = URL(fileURLWithPath: try #require(config["report_path"].string))
        let recorder = OpenAILiveRecorder(requestLimit: 12)
        var report: OpenAIJSON = [
            "mode": "paired_tool_search", "status": "running", "model": .string(model), "source_sha256": config["source_sha256"],
            "synthetic_prompts": true, "synthetic_tool_results": true, "browser_actions_executed": false, "competitive_score": false,
            "max_requests": 12, "checks": [], "requests": [],
        ]
        var checks: [OpenAIJSON] = []
        func save() throws {
            report["checks"] = .array(checks)
            report["requests"] = .array(recorder.snapshot)
            try report.data().write(to: reportURL, options: .atomic)
        }
        guard let key = ProcessInfo.processInfo.environment["LINEN_OPENAI_LIVE_KEY"] ?? CredentialStore.key(for: ProviderCatalog.openAI), !key.isEmpty else {
            report["status"] = "blocked_missing_credential"
            try save()
            return
        }
        try save()
        do {
            guard OpenAIToolSearch.supports(model) else { throw OpenAILiveFailure.invariant }
            let toolkit = AgentToolkit(browser: BrowserModel(database: .temporary()), media: MediaCenter(), log: ConversationLog(database: .temporary()))
            let tools = makeAgentTools(toolkit: toolkit) + [UpdateProgressTool()]
            report["local_tool_count"] = .integer(Int64(tools.count))
            let scenarios: [Scenario] = [
                .init(id: "tabs", prompt: "List the titles of all open browser tabs. Use the browser tool; do not ask a question or change tabs.",
                      tool: "listTabs", result: "Open tabs: Fixture documentation, Fixture dashboard."),
                .init(id: "checkbox",
                      prompt: "On page fixture-page, observation fixture-observation, checkbox ref 7 is unchecked. Set it to checked without submitting. Use the dedicated state-setting tool.",
                      tool: "setChecked", result: "Checkbox ref 7 is checked. No form was submitted."),
                .init(id: "dropdown",
                      prompt: "On page fixture-page, observation fixture-observation, inspect dropdown ref 3 and list its available options from offset 0. Do not change the selection.",
                      tool: "inspectControl", result: "Options: Blue, Green. Current selection: Blue."),
            ]
            for (index, scenario) in scenarios.enumerated() {
                for deferred in index.isMultiple(of: 2) ? [false, true] : [true, false] {
                    let label = scenario.id + (deferred ? "_deferred" : "_direct")
                    recorder.select(label + "_proposal")
                    var settings = OpenAIResponseSettings()
                    settings.useToolSearch = deferred
                    settings.additionalParameters = ["parallel_tool_calls": false]
                    let endpoint = URL(string: "https://api.openai.com/v1")!
                    var client = OpenAIResponsesClient(endpoint: endpoint, apiKey: key, model: model, settings: settings,
                        transport: OpenAILiveTransport(base: OpenAIHTTPTransport(baseURL: endpoint, apiKey: key), recorder: recorder))
                    let first = try await client.respond(transcript: Transcript(), prompt: scenario.prompt, images: [], state: client.restoring(nil),
                                                         tools: tools, maxTokens: 1_024, onText: { _ in })
                    guard first.calls.count == 1, let call = first.calls.first, call.toolName == scenario.tool else { throw OpenAILiveFailure.invariant }
                    let arguments = try OpenAIJSON.decode(Data(call.arguments.jsonString.utf8))
                    if scenario.id != "tabs" {
                        guard arguments["page"] == "fixture-page", arguments["observationID"] == "fixture-observation" else { throw OpenAILiveFailure.invariant }
                        if scenario.id == "checkbox" {
                            guard arguments["ref"] == 7, arguments["checked"] == true else { throw OpenAILiveFailure.invariant }
                        } else {
                            guard arguments["ref"] == 3, arguments["offset"] == 0 else { throw OpenAILiveFailure.invariant }
                        }
                    }
                    let searched = first.state.items.contains { $0["type"] == "tool_search_output" }
                    guard !deferred || searched else { throw OpenAILiveFailure.invariant }
                    var entries = Array(first.transcript)
                    entries.append(.toolOutput(.init(id: call.id, toolName: call.toolName, segments: [.text(.init(content: scenario.result))])))
                    client.settings.additionalParameters["tool_choice"] = "none"
                    recorder.select(label + "_continuation")
                    let second = try await client.respond(transcript: Transcript(entries: entries), prompt: "Report the observed result in one sentence.", images: [],
                                                          state: first.state, tools: tools, maxTokens: 256, onText: { _ in })
                    guard second.calls.isEmpty, !second.text.isEmpty else { throw OpenAILiveFailure.invariant }
                    checks.append(["name": .string(label), "passed": true, "expected_tool": .string(scenario.tool), "arguments_verified": true,
                                   "hosted_discovery_observed": .bool(searched), "native_continuation_passed": true,
                    ])
                    try save()
                }
            }
            report["status"] = "passed"
        } catch {
            report["status"] = "failed"
            report["error"] = .string(OpenAILiveRecorder.errorCode(error))
            Issue.record("Paired tool discovery failed; see the sanitized report.")
        }
        try save()
    }
}
