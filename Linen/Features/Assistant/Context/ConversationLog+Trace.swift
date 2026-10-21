// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension ConversationLog {
    nonisolated struct Usage: Codable, Equatable, Sendable {
        var requestCount = 0
        var inputTokens = 0
        var cachedTokens = 0
        var outputTokens = 0
        var estimatedContextTokens = 0
        var contextBreakdown: ContextBreakdown?

        static let zero = Usage()
    }

    nonisolated struct ActivityLink: Codable, Identifiable, Equatable, Sendable {
        let id: UUID
        let title: String
        let url: URL

        init(id: UUID = UUID(), title: String, url: URL) {
            self.id = id
            self.title = title
            self.url = url
        }
    }

    nonisolated struct Step: Codable, Identifiable, Equatable, Sendable {
        enum Kind: String, Codable, Equatable {
            case thinking
            case tool
        }

        enum State: String, Codable, Equatable {
            case running
            case completed
            case failed
        }

        let id: UUID
        let kind: Kind
        let title: String
        let toolName: String?
        let startedAt: Date
        var state: State

        init(kind: Kind, title: String, toolName: String? = nil, state: State = .running) {
            id = UUID()
            self.kind = kind
            self.title = title
            self.toolName = toolName
            self.startedAt = Date()
            self.state = state
        }

        init(id: UUID, kind: Kind, title: String, toolName: String?, startedAt: Date, state: State) {
            self.id = id
            self.kind = kind
            self.title = title
            self.toolName = toolName
            self.startedAt = startedAt
            self.state = state
        }
    }

    nonisolated struct TaskTrace: Codable, Identifiable, Equatable, Sendable {
        enum State: String, Codable, Equatable {
            case running
            case completed
            case cancelled
            case failed
            case paused

            var isSpoken: Bool {
                self == .completed || self == .cancelled || self == .paused
            }
        }

        let id: UUID
        var tabID: UUID
        var prompt: String
        let startedAt: Date
        var steps: [Step]
        var response: String
        var state: State
        var finishedAt: Date?
        let providerID: String?
        var attachments: [AssistantAttachment] = []
        var attachmentTextOnly = false
        var stopReason: AgentStopReason?
        var diagnostics = AgentRunDiagnostics()
        var checkpoint: AgentCheckpoint?
        var clearsContext = false
        var openedTabIDs: [UUID] = []

        var progressUpdates: [AgentProgressUpdate] {
            checkpoint?.progressUpdates ?? []
        }

        var memoryUpdates: [AgentMemoryUpdate] {
            checkpoint?.memoryUpdates ?? []
        }

        var hasUserPrompt: Bool {
            !prompt.isEmpty && prompt != AgentCheckpoint.resumePrompt
        }

        var canContinue: Bool {
            state == .paused || state == .cancelled || state == .failed
        }
    }

    struct Exchange: Equatable {
        let prompt: String
        let response: String
        var attachments: [AssistantAttachment] = []
        var attachmentTextOnly = false
    }
}
