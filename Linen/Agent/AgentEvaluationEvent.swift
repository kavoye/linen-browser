// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct AgentEvaluationEvent: Codable, Equatable, Sendable {
    let kind: String
    let values: [String: String]

    init(kind: String, values: [String: String]) {
        let kinds: Set<String> = [
            "generation", "response", "tool_proposed", "tool_accepted", "tool_completed",
            "tool_failed", "tool_stopped", "terminal", "context_compaction", "overflow_recovery",
            "progress_recovery", "checkpoint", "resume", "compaction_result", "progress_update",
            "provider_usage", "provider_failure", "first_text",
        ]
        self.kind = kinds.contains(kind) ? kind : "unknown"
        var safe: [String: String] = [:]
        if let name = values["name"] {
            safe["name"] = AgentDiagnosticPrivacy.tool(name)
        }
        let statuses: Set<String> = [
            "completed", "cancelled", "agent_error", "budget_exceeded", "request_limit",
            "no_progress", "context_limit", "provider_error", "interrupted", "input_budget",
            "failed", "succeeded", "not_executed", "manual", "empty_summary", "not_smaller", "summary_too_large",
            "verification_required", "blocked", "answered", "verified", "unverified",
        ]
        for key in ["status", "reason"] {
            if let value = values[key], statuses.contains(value) {
                safe[key] = value
            }
        }
        let failureKinds: Set<String> = [
            "configuration", "http", "invalidResponse", "incomplete", "streamInterrupted",
            "contextLimit", "unsupportedAction", "network", "other",
        ]
        if let value = values["failure_kind"], failureKinds.contains(value) {
            safe["failure_kind"] = value
        }
        let apiCodes: Set<String> = [
            "server_error", "server_is_overloaded", "service_unavailable", "rate_limit_exceeded", "slow_down",
            "credit_balance_exhausted", "organization_spend_limit_exceeded", "project_spend_limit_exceeded",
            "organization_usage_limit_exceeded", "context_length_exceeded",
            "previous_response_not_found", "websocket_connection_limit_reached", "websocket_stream_limit_reached",
            "invalid_stream_id", "invalid_api_key", "invalid_request_error", "insufficient_quota", "billing_hard_limit_reached",
        ]
        if let value = values["api_code"], apiCodes.contains(value) {
            safe["api_code"] = value
        }
        if let value = values["http_status"], let status = Int(value), (100...599).contains(status) {
            safe["http_status"] = String(status)
        }
        for key in ["elapsed_ms", "input_tokens", "output_tokens", "cached_tokens", "cache_write_tokens", "reasoning_tokens",
                    "total_tokens", "count", "output_bytes", "output_images", ] {
            if let value = values[key], let number = Int(value), number >= 0 {
                safe[key] = String(number)
            }
        }
        self.values = safe
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: try container.decode(String.self, forKey: .kind),
            values: try container.decode([String: String].self, forKey: .values)
        )
    }
}
