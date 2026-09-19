// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum AutofillSaveKind: String, Codable, CaseIterable, Sendable {
    case password, card, contact
}

nonisolated enum AutofillSaveCandidate: Sendable {
    case password(SavedPassword)
    case card(PaymentCard)
    case contact(AutofillContact)

    var kind: AutofillSaveKind {
        switch self {
        case .password:
            .password
        case .card:
            .card
        case .contact:
            .contact
        }
    }

    var identity: [String] {
        switch self {
        case .password(let login):
            [login.origin, login.username]
        case .card(let card):
            [card.number]
        case .contact:
            values
        }
    }

    var values: [String] {
        switch self {
        case .password(let login):
            [login.origin, login.username, login.password]
        case .card(let card):
            [card.number, card.cardholder, card.month.map(String.init) ?? "", card.year.map(String.init) ?? ""]
        case .contact(let contact):
            [contact.givenName, contact.familyName, contact.organization, contact.email, contact.phone,
             contact.street, contact.city, contact.region, contact.postalCode, contact.countryCode, ]
        }
    }

    var summary: String {
        switch self {
        case .password(let login):
            login.username.isEmpty ? login.origin : login.username
        case .card(let card):
            card.summary.label
        case .contact(let contact):
            contact.detail
        }
    }
}
