// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct AgentExecutionPolicy: Equatable, Sendable {
    @TaskLocal static var scoped: Self?
    var maxModelRequests: Int?
    var repeatedActionLimit = 3
    var consecutiveFailureLimit = 3

    static let interactive = Self()

    static var current: Self {
        if let scoped {
            return scoped
        }
        let limit = UserDefaults.standard.integer(forKey: settingsKey)
        return Self(maxModelRequests: limit > 0 ? limit : nil)
    }

    static let settingsKey = "assistant.maxModelRequests"
}

nonisolated enum AgentStopReason: String, Codable, Sendable {
    case requestLimit = "request_limit"
    case noProgress = "no_progress"
    case contextLimit = "context_limit"
    case providerError = "provider_error"
    case interrupted

    var message: String {
        switch self {
        case .requestLimit:
            String(localized: "Paused at your request limit. Your progress is saved; choose Continue to keep going.")
        case .noProgress:
            String(localized: "Paused because the last actions weren’t making progress. Your progress is saved; check the page, then choose Continue.")
        case .contextLimit:
            String(localized: "Paused because the conversation couldn’t be compacted safely. Your progress is saved.")
        case .providerError:
            String(localized: "Couldn’t reach the model provider. Your progress is saved; check the connection, then choose Continue.")
        case .interrupted:
            String(localized: "Stopped. Your progress is saved; choose Continue to resume.")
        }
    }
}
