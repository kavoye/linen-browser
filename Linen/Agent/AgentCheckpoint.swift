// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation

nonisolated struct AgentCheckpoint: Codable, Equatable, Sendable {
    var transcript = Transcript()
    var summary = ""
    var userAnswers: [String] = []
    var progressUpdates: [AgentProgressUpdate]?
    var openAI: OpenAIConversationState?
    var taskLedger: AgentTaskLedger?
    var completion: AgentTaskLedger.Completion?

    static let resumePrompt = """
        Continue the unfinished task from the saved conversation. First read the current page: \
        the user may have changed it. Verify any action whose result is unknown before deciding \
        whether it is still needed. Do not repeat completed actions or ask for answers already given.
        """
}
