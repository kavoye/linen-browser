// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct AgentExecutionPolicy: Equatable, Sendable {
    @TaskLocal static var scoped: Self?
    var maxModelRequests: Int?
    var repeatedActionLimit = 3
    var consecutiveFailureLimit = 3
    var requiresOutcomeVerification = true

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
    case rateLimited = "rate_limited"
    case interrupted
    case verificationRequired = "verification_required"
    case blocked

    var message: String {
        switch self {
        case .verificationRequired:
            String(localized: "The assistant hasn’t confirmed the result yet. Choose Continue to check it.")
        case .blocked:
            String(localized: "This task needs your help before it can go on. Your progress is saved.")
        case .requestLimit:
            String(localized: "Paused at the request limit you set. Choose Continue to keep going.")
        case .noProgress:
            String(localized: "Paused because the same actions kept repeating or failing. Check the page, then choose Continue.")
        case .contextLimit:
            String(localized: "Paused because the conversation is too long. Your progress is saved.")
        case .rateLimited:
            String(localized: "You’ve reached the model provider’s rate limit. Wait a moment, then choose Continue.")
        case .providerError:
            String(localized: "The model request failed. Choose Continue to try again.")
        case .interrupted:
            String(localized: "Stopped. Choose Continue to resume.")
        }
    }
}
