// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum AgentStopReason: String, Codable, Sendable {
    case noProgress = "no_progress"
    case contextLimit = "context_limit"
    case providerError = "provider_error"
    case rateLimited = "rate_limited"
    case interrupted

    init(from decoder: any Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .interrupted
    }

    var message: String {
        switch self {
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
