// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum AgentProviderRetry {
    static func delay(for error: any Error, attempt: Int, remoteActionsEnabled: Bool, jitter: Double = Double.random(in: 0...0.25)) -> Double? {
        guard attempt < 2, !remoteActionsEnabled else { return nil }
        if let failure = error as? OpenAIFailure {
            guard failure.kind == .http, failure.usage == nil,
                  [429, 500, 502, 503, 504].contains(failure.status ?? 0),
                  !["insufficient_quota", "billing_hard_limit_reached"].contains(failure.code ?? "") else { return nil }
            if let delay = failure.retryAfter {
                // Honor Retry-After without holding an interactive request for over a minute.
                guard delay.isFinite, delay >= 0, delay <= 60 else { return nil }
                return delay
            }
        } else if let network = error as? URLError {
            guard [.cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet].contains(network.code) else { return nil }
        } else { return nil }
        return pow(2, Double(attempt)) + max(0, min(jitter, 0.25))
    }

    static func retryAfter(_ value: String?, milliseconds: String? = nil, now: Date = Date()) -> Double? {
        if let milliseconds, let number = Double(milliseconds), number.isFinite, number >= 0 {
            return number / 1_000
        }
        guard let value else { return nil }
        if let number = Double(value), number.isFinite, number >= 0 {
            return number
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSince(now)) }
    }
}
