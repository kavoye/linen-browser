// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import GRDB

extension ConversationLog {
    nonisolated struct TraceRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
        static let databaseTableName = "agentTrace"

        var id: UUID
        var tabID: UUID
        var prompt: String
        var startedAt: Date
        var response: String
        var state: TaskTrace.State
        var finishedAt: Date?
        var providerID: String?
        var stopReason: AgentStopReason?
        var diagnostics: Data?
        var clearsContext: Bool
        var openedTabIDs: String?
    }

    nonisolated struct MemoryRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
        static let databaseTableName = "agentConversationMemory"
        let traceID: UUID
        let payload: Data
    }

    nonisolated struct AttachmentRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
        static let databaseTableName = "agentAttachments"
        let traceID: UUID
        let payload: Data
        let textOnly: Bool
    }

    nonisolated struct StepRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
        static let databaseTableName = "agentStep"

        var id: UUID
        var traceID: UUID
        var position: Int
        var kind: Step.Kind
        var title: String
        var toolName: String?
        var startedAt: Date
        var detail: String?
        var links: String
        var state: Step.State
    }

    nonisolated struct UsageRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
        static let databaseTableName = "agentUsage"

        var tabID: UUID
        var requestCount: Int
        var inputTokens: Int
        var cachedTokens: Int
        var outputTokens: Int
        var estimatedContextTokens: Int
    }

    nonisolated static func record(_ trace: TaskTrace) -> TraceRecord {
        TraceRecord(
            id: trace.id,
            tabID: trace.tabID,
            prompt: trace.prompt,
            startedAt: trace.startedAt,
            response: trace.response,
            state: trace.state,
            finishedAt: trace.finishedAt,
            providerID: trace.providerID,
            stopReason: trace.stopReason,
            diagnostics: try? JSONEncoder().encode(trace.diagnostics),
            clearsContext: trace.clearsContext,
            openedTabIDs: trace.openedTabIDs.isEmpty
                ? nil : (try? JSONEncoder().encode(trace.openedTabIDs)).map { String(decoding: $0, as: UTF8.self) }
        )
    }

    nonisolated static func steps(of trace: TaskTrace) -> [StepRecord] {
        trace.steps.enumerated().map { position, step in
            return StepRecord(
                id: step.id,
                traceID: trace.id,
                position: position,
                kind: step.kind,
                title: AgentDiagnosticPrivacy.title(for: step.toolName ?? ""),
                toolName: step.toolName.map(AgentDiagnosticPrivacy.tool),
                startedAt: step.startedAt,
                detail: nil,
                links: "[]",
                state: step.state
            )
        }
    }

    nonisolated static func step(from record: StepRecord) -> Step {
        Step(
            id: record.id,
            kind: record.kind,
            title: AgentDiagnosticPrivacy.title(for: record.toolName ?? ""),
            toolName: record.toolName.map(AgentDiagnosticPrivacy.tool),
            startedAt: record.startedAt,
            state: record.state
        )
    }

    nonisolated static func record(_ usage: Usage, for tabID: UUID) -> UsageRecord {
        UsageRecord(
            tabID: tabID,
            requestCount: usage.requestCount,
            inputTokens: usage.inputTokens,
            cachedTokens: usage.cachedTokens,
            outputTokens: usage.outputTokens,
            estimatedContextTokens: usage.estimatedContextTokens
        )
    }

    nonisolated static func usage(from record: UsageRecord) -> Usage {
        Usage(
            requestCount: record.requestCount,
            inputTokens: record.inputTokens,
            cachedTokens: record.cachedTokens,
            outputTokens: record.outputTokens,
            estimatedContextTokens: record.estimatedContextTokens
        )
    }
}
