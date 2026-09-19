// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

struct BenchAdapterTests {
    private func settings(_ value: String) throws -> BenchSettings {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(BenchSettings.self, from: Data(value.utf8))
    }

    @Test func settingsAreExplicitAndRejectUnsupportedOptions() throws {
        let defaults = try settings("{}")
        #expect(!defaults.headless)
        #expect(defaults.searchMode == .disabled)
        #expect(defaults.maxModelRequests == nil)
        #expect(!defaults.toolSearch)
        #expect(!defaults.computerUse)
        #expect(try settings(#"{"tool_search":true}"#).toolSearch)
        let search = try settings(#"{"tool_search":true}"#)
        #expect(try search.openAIOptions(model: "gpt-5.6-luna", adapter: .openAIResponses).useToolSearch)
        #expect(throws: BenchSettings.ConfigurationError.self) { try search.openAIOptions(model: "gpt-4.1", adapter: .openAIResponses) }
        #expect(throws: BenchSettings.ConfigurationError.self) { try search.openAIOptions(model: "gpt-5.6-luna", adapter: .openAICompatible) }
        let live = try settings(#"{"search_mode":"live","headless":true,"max_model_requests":20,"reasoning_effort":"medium"}"#)
        #expect(live.searchMode == .live)
        #expect(live.headless)
        #expect(live.maxModelRequests == 20)
        #expect(live.reasoningEffort == "medium")
        for invalid in [#"{"unknown":true}"#, #"{"headless":"yes"}"#, #"{"max_model_requests":0}"#, #"{"search_mode":"magic"}"#] {
            #expect(throws: (any Error).self) { try settings(invalid) }
        }
        #expect(throws: (any Error).self) { try settings(#"{"tool_search":"true"}"#) }
    }

    @Test func computerUseRequiresANativeProviderAndMountedPage() throws {
        let enabled = try settings(#"{"computer_use":true}"#)
        #expect(try enabled.openAIOptions(model: "gpt-5.6-luna", adapter: .openAIResponses).useComputer)
        #expect(throws: BenchSettings.ConfigurationError.self) { try enabled.openAIOptions(model: "gpt-5.6-luna", adapter: .openAICompatible) }
        let headless = try settings(#"{"computer_use":true,"headless":true}"#)
        #expect(throws: BenchSettings.ConfigurationError.self) { try headless.openAIOptions(model: "gpt-5.6-luna", adapter: .openAIResponses) }
        #expect(throws: (any Error).self) { try settings(#"{"computer_use":"true"}"#) }
        let hybrid = try settings(#"{"computer_use":true,"tool_search":true}"#)
        let options = try hybrid.openAIOptions(model: "gpt-5.6-luna", adapter: .openAIResponses)
        #expect(options.useComputer && options.useToolSearch)
    }

    @Test(arguments: ["completed", "no_progress", "request_limit", "context_limit", "provider_error", "interrupted"])
    func nativeStopsMapToThePublishedProtocol(_ native: String) {
        var telemetry = BenchTelemetry()
        telemetry.events = [.init(kind: "terminal", values: ["status": native])]
        let expected = ["completed": "completed", "no_progress": "budget_exceeded", "request_limit": "budget_exceeded",
                        "context_limit": "budget_exceeded", "provider_error": "agent_error", "interrupted": "cancelled",
        ]
        #expect(telemetry.status(timedOut: false, cancelled: false) == expected[native])
        #expect(telemetry.status(timedOut: true, cancelled: false) == "timeout")
        #expect(telemetry.status(timedOut: true, cancelled: true) == "cancelled")
    }

    @Test func nativeMetricsDoNotPretendToMeasureProviderTokens() {
        var telemetry = BenchTelemetry()
        telemetry.events = [
            .init(kind: "generation", values: [:]),
            .init(kind: "response", values: ["elapsed_ms": "50"]),
            .init(kind: "tool_accepted", values: ["name": "readPage"]),
            .init(kind: "tool_accepted", values: ["name": OpenAIComputerCall.toolName]),
            .init(kind: "tool_completed", values: ["output_bytes": "400", "elapsed_ms": "20"]),
            .init(kind: "tool_failed", values: ["output_bytes": "100", "elapsed_ms": "10"]),
            .init(kind: "progress_recovery", values: [:]),
        ]
        telemetry.consentRequests = 1
        telemetry.userQuestions = 2
        #expect(telemetry.usage["tool_output_bytes"] == 500)
        #expect(telemetry.usage["computer_calls"] == 1)
        #expect(telemetry.usage["native_actions"] == 2)
        #expect(telemetry.usage["tool_elapsed_ms"] == 30)
        #expect(telemetry.usage["agent_response_elapsed_ms"] == 50)
        #expect(telemetry.usage["failed_tools"] == 1)
        #expect(telemetry.usage["recovery_attempts"] == 1)
        #expect(telemetry.usage["consent_requests"] == 1)
        #expect(telemetry.usage["user_questions"] == 2)
        #expect(telemetry.usage["model_calls"] == nil)
        #expect(telemetry.usage["input_tokens"] == nil)
    }
}
