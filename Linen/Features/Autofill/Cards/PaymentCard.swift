// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct PaymentCard: Codable, Identifiable, Sendable, Equatable {
    var id: UUID
    let number: String
    let cardholder: String
    let month: Int?
    let year: Int?
    var securityCode: String?

    init(number: String, cardholder: String = "", month: Int? = nil, year: Int? = nil, securityCode: String? = nil) throws {
        let digits = number.filter { $0 != " " && $0 != "-" }
        guard Self.isValidNumber(digits) else { throw PaymentCardError.invalidNumber }
        guard month.map({ (1...12).contains($0) }) ?? true,
              year.map({ (2000...2199).contains($0) }) ?? true
        else { throw PaymentCardError.invalidExpiry }
        let code = securityCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let code, !code.isEmpty {
            guard (3...4).contains(code.utf8.count), code.utf8.allSatisfy({ (48...57).contains($0) })
            else { throw PaymentCardError.invalidSecurityCode }
        }
        self.securityCode = code?.isEmpty == false ? code : nil
        id = UUID()
        self.number = digits
        self.cardholder = String(cardholder.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        self.month = month
        self.year = year
    }

    var summary: Summary {
        Summary(id: id, network: network, lastFour: String(number.suffix(4)), month: month, year: year)
    }

    var network: String {
        if number.hasPrefix("4") { return "Visa" }
        if number.hasPrefix("34") || number.hasPrefix("37") { return "American Express" }
        if let prefix = Int(number.prefix(2)), (51...55).contains(prefix) { return "Mastercard" }
        if let prefix = Int(number.prefix(4)), (2221...2720).contains(prefix) { return "Mastercard" }
        if number.hasPrefix("6011") || number.hasPrefix("65") { return "Discover" }
        if number.hasPrefix("35") { return "JCB" }
        if number.hasPrefix("62") { return "UnionPay" }
        return String(localized: "Payment card")
    }

    func isExpired(on date: Date = .now) -> Bool {
        guard let month, let year else { return false }
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: date)
        guard let currentYear = parts.year, let currentMonth = parts.month else { return false }
        return year < currentYear || (year == currentYear && month < currentMonth)
    }

    static func isValidNumber(_ number: String) -> Bool {
        let digits = Array(number.utf8)
        guard (13...19).contains(digits.count), digits.allSatisfy({ (48...57).contains($0) }),
              digits.contains(where: { $0 != 48 }) else { return false }
        if number.hasPrefix("62") { return true }
        let sum = digits.reversed().enumerated().reduce(0) { total, item in
            let digit = Int(item.element - 48) * (item.offset.isMultiple(of: 2) ? 1 : 2)
            return total + (digit > 9 ? digit - 9 : digit)
        }
        return sum.isMultiple(of: 10)
    }

    static func merging(_ incoming: [Self], into existing: [Self], preservingMissingSecurityCodes: Bool = false) -> [Self] {
        var result = existing
        for var card in incoming {
            if let index = result.firstIndex(where: { $0.id == card.id }) ?? result.firstIndex(where: { $0.number == card.number }) {
                if preservingMissingSecurityCodes, card.securityCode == nil, card.number == result[index].number {
                    card.securityCode = result[index].securityCode
                }
                card.id = result[index].id
                result[index] = card
                result.removeAll { $0.number == card.number && $0.id != card.id }
            } else {
                result.append(card)
            }
        }
        return result
    }

    nonisolated struct Summary: Identifiable, Equatable, Sendable {
        let id: UUID
        let network: String
        let lastFour: String
        let month: Int?
        let year: Int?

        var label: String {
            "\(network) •••• \(lastFour)"
        }
    }
}

nonisolated enum PaymentCardError: Error, LocalizedError {
    case invalidNumber
    case invalidSecurityCode
    case invalidExpiry
    case invalidExport
    case tooLarge
    case keychain(Int32)
    case privateBrowsing
    case changedPage
    case noField

    var errorDescription: String? {
        switch self {
        case .invalidNumber:
            String(localized: "Enter a valid payment card number.")
        case .invalidSecurityCode:
            String(localized: "Enter a three- or four-digit security code, or leave it empty.")
        case .invalidExpiry:
            String(localized: "Enter an expiration month from 1 to 12 and a four-digit year.")
        case .invalidExport:
            String(localized: "Choose the ZIP exported by Safari or its PaymentCards.json file.")
        case .tooLarge:
            String(localized: "This export is too large. Unzip it and choose PaymentCards.json.")
        case .keychain:
            String(localized: "Linen couldn’t unlock or save your cards in Keychain. Try again in a signed build.")
        case .privateBrowsing:
            String(localized: "Saved payment cards aren’t available in Private Browsing.")
        case .changedPage:
            String(localized: "The payment page changed. Select the payment field and try again.")
        case .noField:
            String(localized: "Select a card number, cardholder name, or expiration field to fill a card.")
        }
    }
}
