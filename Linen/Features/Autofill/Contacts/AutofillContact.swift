// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Contacts
import Foundation

nonisolated struct AutofillContact: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var label = ""
    var givenName = ""
    var familyName = ""
    var organization = ""
    var email = ""
    var phone = ""
    var street = ""
    var city = ""
    var region = ""
    var postalCode = ""
    var countryCode = ""

    var name: String {
        [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var title: String {
        [label, name, email, street, organization, phone].first { !$0.isEmpty } ?? String(localized: "Contact")
    }

    var detail: String {
        [name, email, phone, street, city, region, postalCode, countryCode]
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }

    var isValid: Bool {
        let values = [label, givenName, familyName, organization, email, phone, street, city, region, postalCode, countryCode]
        return values.allSatisfy { $0.count <= 500 }
            && values.dropFirst().contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && (countryCode.isEmpty || Locale.Region.isoRegions.contains { $0.identifier == countryCode })
    }

    var fields: [String: String] {
        let lines = street.components(separatedBy: .newlines).filter { !$0.isEmpty }
        return [
            "name": name, "given-name": givenName, "family-name": familyName,
            "organization": organization, "email": email, "tel": phone,
            "street-address": street, "address-line1": lines.first ?? "",
            "address-line2": lines.dropFirst().first ?? "", "address-line3": lines.dropFirst(2).joined(separator: ", "),
            "address-level2": city, "address-level1": region, "postal-code": postalCode,
            "country": countryCode, "country-name": Locale.current.localizedString(forRegionCode: countryCode) ?? countryCode,
        ]
    }

    init() {}

    init(contact: CNContact) {
        if contact.isKeyAvailable(CNContactGivenNameKey) {
            givenName = contact.givenName
        }
        if contact.isKeyAvailable(CNContactFamilyNameKey) {
            familyName = contact.familyName
        }
        if contact.isKeyAvailable(CNContactOrganizationNameKey) {
            organization = contact.organizationName
        }
        if contact.isKeyAvailable(CNContactEmailAddressesKey) {
            email = contact.emailAddresses.first?.value as String? ?? ""
        }
        if contact.isKeyAvailable(CNContactPhoneNumbersKey) {
            phone = contact.phoneNumbers.first?.value.stringValue ?? ""
        }
        if contact.isKeyAvailable(CNContactPostalAddressesKey), let address = contact.postalAddresses.first?.value {
            apply(address)
        }
    }

    mutating func apply(_ address: CNPostalAddress) {
        street = address.street
        city = address.city
        region = address.state
        postalCode = address.postalCode
        countryCode = address.isoCountryCode.uppercased()
    }
}
