// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation

nonisolated struct AgentProgressUpdate: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    let text: String
    let afterStepCount: Int
}

nonisolated struct UpdateProgressTool: Tool {
    static let toolName = "updateProgress"
    let name = Self.toolName
    let description = "Give the user a brief progress update about your next action or an observed finding. This displays commentary and does not finish the task."

    @Generable struct Arguments {
        @Guide(description: "One or two concise sentences for the user: what you are doing, what you found, or what comes next. No hidden reasoning or sensitive field values.")
        var message: String
    }

    func call(arguments: Arguments) async throws -> String {
        "Progress update delivered. Continue the task."
    }
}
