// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct AutofillSuggestion: Codable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let detail: String
    let origin: String?
    let month: Int?
    let year: Int?

    init(_ candidate: AutofillSaveCandidate) {
        switch candidate {
        case .password(let login):
            id = login.id
            title = login.username.isEmpty ? login.origin : login.username
            detail = login.origin
            origin = login.origin
            month = nil; year = nil
        case .card(let card):
            id = card.id
            title = card.summary.label
            detail = card.cardholder
            origin = nil
            month = card.month; year = card.year
        case .contact(let contact):
            id = contact.id
            title = contact.title
            detail = [contact.email, contact.street.replacingOccurrences(of: "\n", with: ", ")]
                .filter { !$0.isEmpty }.joined(separator: " · ")
            origin = nil
            month = nil; year = nil
        }
    }

    var isExpired: Bool {
        guard let month, let year else { return false }
        let now = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: .now)
        guard let currentYear = now.year, let currentMonth = now.month else { return false }
        return year < currentYear || (year == currentYear && month < currentMonth)
    }
}
