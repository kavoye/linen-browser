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

    @Test func readsSafariSchemaAndSkipsBadCards() throws {
        let data = Data(#"""
        {"metadata":{"data_type":"payment_cards","schema_version":1},"payment_cards":[
          {"card_number":"4242 4242 4242 4242","cardholder_name":"Ada Example","card_expiration_month":9,"card_expiration_year":2030},
          {"card_number":"5555555555554444"},
          {"card_number":"bad"},
          {"card_number":"378282246310005","card_expiration_month":15}
        ]}
        """#.utf8)
        let result = try SafariCardImport.decode(data)
        #expect(result.cards.count == 2)
        #expect(result.skipped == 2)
        #expect(result.cards[0].cardholder == "Ada Example")
        #expect(result.cards[0].month == 9)
        #expect(result.cards[1].year == nil)
    }

    @Test func refusesOtherExportsAndOversizedInput() {
        for json in ["{}", #"{"history":[]}"#, #"{"payment_cards":"wrong"}"#,
                     #"{"metadata":{"data_type":"history"},"payment_cards":[]}"#,
                    ] {
            #expect(throws: PaymentCardError.self) { try SafariCardImport.decode(Data(json.utf8)) }
        }
        #expect(throws: PaymentCardError.self) {
            try SafariCardImport.decode(Data(repeating: 32, count: SafariCardImport.maximumJSONBytes + 1))
        }
    }

    @Test func readsAnExportedZIPWithoutExtractingItsContents() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Cartes.json")
        try Data(#"{"payment_cards":[{"card_number":"4242424242424242"}]}"#.utf8).write(to: source)
        let archive = directory.appendingPathComponent("Safari.zip")
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/zip")
        process.currentDirectoryURL = directory
        process.arguments = ["-q", archive.path, source.lastPathComponent]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        try FileManager.default.removeItem(at: source)
        let result = try SafariCardImport.read(archive)
        #expect(result.cards.count == 1)
        #expect(!FileManager.default.fileExists(atPath: source.path))
    }

    @Test func privateBrowsingNeverOpensTheKeychain() async {
        await #expect(throws: PaymentCardError.self) {
            try await PaymentCardVault(profileID: Profile.privateID).cards()
        }
    }
}
