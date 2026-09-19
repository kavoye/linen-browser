// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct AgentTurnResult: Sendable {
    let taskID: UUID
    let text: String
}

extension AgentTurnModel {
    func perform(utterance: String) async throws -> AgentTurnResult {
        let ownership = AgentTurnOwnership()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let started = run(
                    utterance: utterance, showsInChrome: false, speechOverride: SilentAgentSpeech(),
                    completion: { continuation.resume(with: $0) }
                )
                ownership.taskID = activeTask?.id
                if !started {
                    continuation.resume(throwing: AgentTurnUnavailable())
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, let taskID = ownership.taskID, activeTask?.id == taskID else { return }
                cancel()
            }
        }
    }
}

private struct AgentTurnUnavailable: Error {}

@MainActor
private final class AgentTurnOwnership {
    var taskID: UUID?
}

@MainActor
private final class SilentAgentSpeech: SpeechOutput {
    var isMuted = true
    var onSpeakingChange: ((Bool) -> Void)?
    func speak(_ text: String) {}
    func stopSpeaking() {}
}
