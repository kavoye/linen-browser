// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import os

@MainActor
final class AgentToolProposalObserver: ToolExecutionDelegate {
    var calls: [Transcript.ToolCall] = []

    func propose(name: String, arguments: GeneratedContent) {
        calls.append(.init(id: UUID().uuidString, toolName: name, arguments: arguments))
    }

    func didGenerateToolCalls(_ calls: [Transcript.ToolCall], in session: LanguageModelSession) async {
        self.calls = calls
    }

    func toolCallDecision(for call: Transcript.ToolCall, in session: LanguageModelSession) async -> ToolExecutionDecision {
        .stop
    }
}

nonisolated enum AgentToolProposalScope {
    @TaskLocal static var current: AgentToolProposalObserver?
}
