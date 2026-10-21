// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct GitHubRateLimit {
    var retryAfter: Date?
    private var strikes = 0

    var isThrottled: Bool {
        retryAfter.map { $0 > .now } ?? false
    }

    mutating func note(limitedUntil date: Date) {
        strikes += isThrottled ? 0 : 1
        let backoff = min(900, 60 * pow(2, Double(min(strikes, 5) - 1)))
        retryAfter = max(retryAfter ?? date, date, .now.addingTimeInterval(backoff))
    }

    mutating func recovered() {
        strikes = 0
    }

    mutating func reset() {
        strikes = 0
        retryAfter = nil
    }
}
