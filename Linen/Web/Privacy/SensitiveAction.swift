// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum SensitiveAction {
    enum Category: String, Codable, CaseIterable, Sendable {
        case purchase
        case transfer
        case deletion
        case publication

        var consequence: LocalizedStringResource {
            switch self {
            case .purchase:
                "completes a purchase"
            case .transfer:
                "moves money"
            case .deletion:
                "permanently deletes something"
            case .publication:
                "posts or sends something in your name"
            }
        }

        var consequenceForModel: String {
            switch self {
            case .purchase:
                "completes a purchase"
            case .transfer:
                "moves money"
            case .deletion:
                "permanently deletes something"
            case .publication:
                "posts or sends something in your name"
            }
        }

        var label: LocalizedStringResource {
            switch self {
            case .purchase:
                "Purchases"
            case .transfer:
                "Money transfers"
            case .deletion:
                "Deletions"
            case .publication:
                "Posting and sending"
            }
        }

        var listName: LocalizedStringResource {
            switch self {
            case .purchase:
                "purchases"
            case .transfer:
                "money transfers"
            case .deletion:
                "deletions"
            case .publication:
                "posting and sending"
            }
        }
    }

    static func category(of label: String, context: String = "") -> Category? {
        let padded = " \(normalized(label + " " + context)) "
        guard padded.count > 2 else { return nil }
        for (signal, category) in signalsByLength where padded.contains(" \(signal) ") {
            return category
        }
        return nil
    }

    static func isConsequentialClick(_ label: String) -> Bool {
        category(of: label) != nil
    }

    static func declined(_ label: String, category: Category) -> String {
        "The user declined “\(label)”. It \(category.consequenceForModel), so it's theirs to do. "
            + "Say what's waiting for them and stop; do not try another way to do it."
    }

    private static func normalized(_ label: String) -> String {
        label
            .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static let signalsByLength: [(String, Category)] =
        signals.sorted { $0.0.count > $1.0.count }

    private static let signals: [(String, Category)] = [
        ("pay", .purchase), ("pay now", .purchase), ("buy now", .purchase),
        ("buy it now", .purchase), ("place order", .purchase),
        ("place your order", .purchase), ("make payment", .purchase),
        ("submit payment", .purchase), ("submit order", .purchase),
        ("complete purchase", .purchase), ("complete order", .purchase),
        ("confirm purchase", .purchase), ("confirm order", .purchase),
        ("confirm payment", .purchase), ("confirm and pay", .purchase),
        ("proceed to pay", .purchase), ("checkout", .purchase),
        ("check out", .purchase), ("place bid", .purchase),
        ("confirm booking", .purchase), ("book now", .purchase),
        ("start subscription", .purchase), ("subscribe and pay", .purchase),

        ("send money", .transfer), ("send payment", .transfer),
        ("confirm transfer", .transfer), ("transfer funds", .transfer),
        ("withdraw", .transfer),

        ("delete account", .deletion), ("delete my account", .deletion),
        ("close account", .deletion), ("deactivate account", .deletion),
        ("permanently delete", .deletion), ("delete forever", .deletion),

        ("post", .publication), ("publish", .publication),
        ("send message", .publication), ("send email", .publication),
        ("send invite", .publication), ("send request", .publication),
        ("submit review", .publication), ("submit post", .publication),
        ("tweet", .publication), ("reply", .publication),
    ]
}
