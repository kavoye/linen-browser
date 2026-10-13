// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

struct PaymentCardTests {
    @Test func normalizesCardNumbersWithoutAcceptingOtherCharacters() throws {
        let card = try PaymentCard(number: "4242 4242-4242 4242", cardholder: "  Ada Example  ", month: 3, year: 2030)
        #expect(card.number == "4242424242424242")
        #expect(card.cardholder == "Ada Example")
        #expect(card.summary.label == "Visa •••• 4242")
        #expect(!card.summary.label.contains(card.number))
        #expect(throws: PaymentCardError.self) { try PaymentCard(number: "4242424242424243") }
        #expect(throws: PaymentCardError.self) { try PaymentCard(number: "0000000000000000") }
        #expect(throws: PaymentCardError.self) { try PaymentCard(number: "4242a424242424242") }
        #expect(throws: PaymentCardError.self) { try PaymentCard(number: "４２４２４２４２４２４２４２４２") }
    }

    @Test func supportsAmexAndUnionPay() throws {
        #expect(try PaymentCard(number: "378282246310005").network == "American Express")
        #expect(try PaymentCard(number: "6200000000000001").network == "UnionPay")
    }

    @Test func refusesInvalidExpiryAndExpiresAtTheEndOfTheMonth() throws {
        #expect(throws: PaymentCardError.self) { try PaymentCard(number: "4242424242424242", month: 0) }
        #expect(throws: PaymentCardError.self) { try PaymentCard(number: "4242424242424242", year: 30) }
        let card = try PaymentCard(number: "4242424242424242", month: 9, year: 2030)
        let calendar = Calendar(identifier: .gregorian)
        let before = try #require(calendar.date(from: DateComponents(year: 2030, month: 9, day: 30, hour: 12)))
        let after = try #require(calendar.date(from: DateComponents(year: 2030, month: 10, day: 1, hour: 12)))
        #expect(!card.isExpired(on: before))
        #expect(card.isExpired(on: after))
    }

    @Test func reimportUpdatesTheExistingCardAndKeepsItsIdentity() throws {
        let first = try PaymentCard(number: "4242424242424242", month: 3, year: 2029)
        let changed = try PaymentCard(number: "4242 4242 4242 4242", month: 8, year: 2032)
        let another = try PaymentCard(number: "5555555555554444")
        let result = PaymentCard.merging([changed, another, another], into: [first])
        #expect(result.count == 2)
        #expect(result[0].id == first.id)
        #expect(result[0].year == 2032)
        #expect(result[1].number == another.number)
    }

    @Test func privateBrowsingNeverOpensTheKeychain() async {
        await #expect(throws: PaymentCardError.self) {
            try await PaymentCardVault(profileID: Profile.privateID).cards()
        }
    }
}
