// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

@testable import Linen

struct BenchTelemetry {
    var events: [AgentEvaluationEvent] = []
    var consentRequests = 0
    var userQuestions = 0

    var usage: [String: Int] {
        [
            "model_generations": events.filter { $0.kind == "generation" }.count,
            "native_actions": events.filter { $0.kind == "tool_accepted" }.count,
            "computer_calls": events.filter { $0.kind == "tool_accepted" && $0.values["name"] == OpenAIComputerCall.toolName }.count,
            "failed_tools": events.filter { $0.kind == "tool_failed" }.count,
            "recovery_attempts": events.filter { $0.kind == "progress_recovery" }.count,
            "compactions": events.filter { $0.kind == "context_compaction" }.count,
            "tool_output_bytes": total("output_bytes", kinds: ["tool_completed", "tool_failed"]),
            "tool_output_images": total("output_images", kinds: ["tool_completed", "tool_failed"]),
            "tool_elapsed_ms": total("elapsed_ms", kinds: ["tool_completed", "tool_failed"]),
            "agent_response_elapsed_ms": total("elapsed_ms", kinds: ["response"]),
            "consent_requests": consentRequests,
            "consent_declined": consentRequests,
            "user_questions": userQuestions,
        ]
    }

    func status(timedOut: Bool, cancelled: Bool) -> String {
        if cancelled { return "cancelled" }
        if timedOut { return "timeout" }
        switch events.last(where: { $0.kind == "terminal" })?.values["status"] {
        case "completed":
            return "completed"
        case "request_limit", "context_limit", "no_progress":
            return "budget_exceeded"
        case "cancelled", "interrupted":
            return "cancelled"
        default:
            return "agent_error"
        }
    }

    private func total(_ field: String, kinds: Set<String>) -> Int {
        events.filter { kinds.contains($0.kind) }.reduce(0) { $0 + (Int($1.values[field] ?? "") ?? 0) }
    }
}
