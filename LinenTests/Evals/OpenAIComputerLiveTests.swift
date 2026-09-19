// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct OpenAIComputerLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LINEN_OPENAI_LIVE_CONFIG"] != nil))
    func nativeComputerWorkflow() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["LINEN_OPENAI_LIVE_CONFIG"])
        let config = try OpenAIJSON.decode(Data(contentsOf: URL(fileURLWithPath: path)))
        guard config["computer_only"] == true, config["live"] == true else { return }
        let model = config["model"].string ?? LLMSettings.model(for: ProviderCatalog.openAI)
        let destination = URL(fileURLWithPath: try #require(config["report_path"].string))
        let recorder = OpenAILiveRecorder(requestLimit: 8)
        var report: OpenAIJSON = [
            "mode": "live_computer_acceptance", "status": "running", "model": .string(model),
            "source_sha256": config["source_sha256"], "synthetic_page": true, "synthetic_usage": false,
            "competitive_score": false, "max_requests": 8, "max_output_tokens_per_response": 2_048,
            "requests": [], "checks": [], "user_pages_accessed": false,
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
            let fixture = try await ComputerWorkflowFixture()
            defer { fixture.close() }
            let endpoint = URL(string: "https://api.openai.com/v1")!
            let transport = OpenAILiveTransport(base: OpenAIHTTPTransport(baseURL: endpoint, apiKey: key), recorder: recorder)
            var settings = OpenAIResponseSettings()
            settings.useComputer = true
            let client = OpenAIResponsesClient(endpoint: endpoint, apiKey: key, model: model, settings: settings, transport: transport)
            recorder.select("computer_browser_workflow")
            await fixture.run(client: client, prompt:
                "Use the computer tool to inspect the current page. Click Choose exactly once and type penguin into Query. "
                    + "Do not submit anything. Verify the final screen, then report completion. The page is already open; do not navigate.")
            let clicks = try await fixture.tab.webView.evaluateJavaScript("window.chosen || 0") as? Int
            let query = try await fixture.tab.webView.evaluateJavaScript("document.querySelector('#query').value") as? String
            let completed = fixture.completed
            if let diagnostics = fixture.log.latestTrace(forTab: fixture.tab.id)?.diagnostics {
                report["workflow_elapsed_ms"] = .integer(Int64(diagnostics.elapsedMilliseconds))
                report["tool_calls"] = .integer(Int64(diagnostics.toolCalls))
                report["failed_tool_calls"] = .integer(Int64(diagnostics.failedToolCalls))
                report["compactions"] = .integer(Int64(diagnostics.compactions))
            }
            let state = fixture.log.checkpoint(forTab: fixture.tab.id)?.openAI
            let outputs = state?.items.filter { $0["type"] == "computer_call_output" }.count ?? 0
            report["checks"] = [
                ["name": "clicked_exactly_once", "passed": .bool(clicks == 1)],
                ["name": "typed_expected_text", "passed": .bool(query == "penguin")],
                ["name": "agent_completed", "passed": .bool(completed)],
                ["name": "native_screenshot_continuation", "passed": .bool(outputs >= 2)],
                ["name": "usage_reported", "passed": .bool(state?.usage?.input != nil && state?.usage?.output != nil)],
            ]
            report["native_screenshots_returned"] = .integer(Int64(outputs))
            let (_, image) = try await PageDriver.computerFrame(in: fixture.tab.webView)
            try image.write(to: destination.deletingLastPathComponent().appendingPathComponent("synthetic-page.jpg"))
            report["status"] = (report["checks"].array ?? []).allSatisfy { $0["passed"] == true } ? "passed" : "failed"
        } catch {
            report["status"] = "failed"
            report["error"] = .string(OpenAILiveRecorder.errorCode(error))
        }
        try save()
        if report["status"] != "passed" { Issue.record("Computer acceptance failed; see the sanitized report.") }
    }
}
