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
            "provider_usage", "first_text",
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
