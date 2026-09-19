// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Contacts
import Foundation
import Testing

@testable import Linen

@MainActor
struct AutofillContactTests {
    private func sample() -> AutofillContact {
        var contact = AutofillContact()
        contact.givenName = "Ada"
        contact.familyName = "Example"
        contact.email = "ada@example.test"
        contact.street = "123 Example Street\nFlat 4"
        contact.countryCode = "GB"
        return contact
    }

    @Test func fieldsPreserveSeparateNamesAndAddressLines() {
        let contact = sample()
        #expect(contact.fields["name"] == "Ada Example")
        #expect(contact.fields["given-name"] == "Ada")
        #expect(contact.fields["address-line1"] == "123 Example Street")
        #expect(contact.fields["address-line2"] == "Flat 4")
        #expect(contact.fields["country"] == "GB")
        #expect(contact.isValid)
        var invalid = contact
        invalid.countryCode = "not-a-country"
        #expect(!invalid.isValid)
        invalid = contact
        invalid.street = String(repeating: "x", count: 501)
        #expect(!invalid.isValid)
        #expect(!AutofillContact().isValid)
    }

    @Test func importsContactDetailsWithoutNotesOrOtherPrivateFields() {
        let source = CNMutableContact()
        source.givenName = "Ada"
        source.familyName = "Example"
        source.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: "ada@example.test" as NSString)]
        source.phoneNumbers = [CNLabeledValue(label: CNLabelHome, value: CNPhoneNumber(stringValue: "+44 1234 567890"))]
        let address = CNMutablePostalAddress()
        address.street = "123 Example Street"
        address.city = "London"
        address.isoCountryCode = "gb"
        source.postalAddresses = [CNLabeledValue(label: CNLabelHome, value: address)]
        let imported = AutofillContact(contact: source)
        #expect(imported.name == "Ada Example")
        #expect(imported.email == "ada@example.test")
        #expect(imported.city == "London")
        #expect(imported.countryCode == "GB")
        #expect(imported.phone == "+44 1234 567890")
    }

    @Test func contactsAreSavedOnlyInTheVaultAndLockClearsMemory() async throws {
        let profile = Profile(id: UUID(), name: "Test", symbol: "person", color: .gray)
        let vault = SecureAutofillVault<AutofillContact>(profileID: profile.id, kind: "contacts", reason: "Test", storage: MemoryAutofillStorage())
        let store = AutofillContactStore(profile: profile, vault: vault)
        await store.load()
        var contact = sample()
        #expect(await store.save(contact))
        contact.label = "Home"
        #expect(await store.save(contact))
        #expect(store.contacts == [contact])
        store.lock()
        #expect(store.contacts.isEmpty)
        #expect(!store.isLoaded)
        await store.load()
        #expect(store.contacts == [contact])
        #expect(await store.remove(contact.id))
        #expect(try await vault.records().isEmpty)
    }

    @Test func privateBrowsingNeverReadsOrWritesSavedContacts() async {
        let profile = Profile.privateBrowsing()
        let storage = MemoryAutofillStorage()
        let vault = SecureAutofillVault<AutofillContact>(profileID: profile.id, kind: "contacts", reason: "Test", storage: storage)
        let store = AutofillContactStore(profile: profile, vault: vault)
        await store.load()
        #expect(!store.isLoaded)
        #expect(await store.save(sample()) == false)
        #expect(storage.itemCount == 0)
    }

    @Test func contactPreferencePersistsAndFollowsProfileSwitches() throws {
        let names = (0..<3).map { "ContactPreferenceTests.\(UUID().uuidString).\($0)" }
        defer { names.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) } }
        let app = try #require(UserDefaults(suiteName: names[0]))
        let first = try #require(UserDefaults(suiteName: names[1]))
        let second = try #require(UserDefaults(suiteName: names[2]))
        let settings = BrowserSettings(defaults: app, sessionDefaults: first)
        #expect(settings.fillsContacts)
        settings.fillsContacts = false
        #expect(!BrowserSettings(defaults: app, sessionDefaults: first).fillsContacts)
        settings.useSessionDefaults(second)
        #expect(settings.fillsContacts)
        settings.useSessionDefaults(first)
        #expect(!settings.fillsContacts)
    }

    @Test func allAutofillControlsAreSearchableOnOnePage() {
        for id in ["autofill.contacts", "autofill.cards", "autofill.passwords", "autofill.applePay"] {
            #expect(SettingsIndex.all.first { $0.id == id }?.category == .autofill)
        }
        #expect(SettingsCategory.autofill.matches("addresses"))
        #expect(SettingsCategory.autofill.matches("passwords"))
    }
}
