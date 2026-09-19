// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct AutofillSaveReview: View {
    let session: AutofillSaveSession
    let offer: AutofillSaveSession.Offer
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var number = ""
    @State private var cardholder = ""
    @State private var month = ""
    @State private var year = ""
    @State private var securityCode = ""
    @State private var contact = AutofillContact()
    @State private var validation: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review Saved Details").font(.headline)
            Text(verbatim: offer.origin).font(Theme.Font.label).foregroundStyle(.secondary)
            Form {
                switch offer.candidate.kind {
                case .password:
                    TextField("Username or email", text: $username)
                    AutofillPasswordField(password: $password)
                case .card:
                    SecureField("Card number", text: $number)
                    TextField("Name on card", text: $cardholder)
                    TextField("Expiration month (MM)", text: $month)
                    TextField("Expiration year (YYYY)", text: $year)
                    SecureField("Security code (optional)", text: $securityCode).privacySensitive()
                case .contact:
                    TextField("First name", text: $contact.givenName)
                    TextField("Last name", text: $contact.familyName)
                    TextField("Company", text: $contact.organization)
                    TextField("Email", text: $contact.email)
                    TextField("Phone", text: $contact.phone)
                    TextField("Street address", text: $contact.street, axis: .vertical).lineLimit(2...3)
                    TextField("City", text: $contact.city)
                    TextField("State or region", text: $contact.region)
                    TextField("Postal code", text: $contact.postalCode)
                    TextField("Country code", text: $contact.countryCode)
                }
            }
            .textFieldStyle(.roundedBorder)
            if let message = validation ?? session.error {
                Text(verbatim: message).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
                    .disabled(session.isBusy || session.current?.id != offer.id)
            }
        }
        .padding(24).frame(width: 460)
        .onAppear {
            switch offer.candidate {
            case .password(let login):
                username = login.username; password = login.password
            case .card(let card):
                number = card.number; cardholder = card.cardholder; securityCode = card.securityCode ?? ""
                month = card.month.map(String.init) ?? ""; year = card.year.map(String.init) ?? ""
            case .contact(let saved):
                contact = saved
            }
        }
        .onChange(of: session.current?.id) { _, id in if id != offer.id { dismiss() } }
        .onDisappear { password = ""; number = ""; securityCode = ""; contact = AutofillContact() }
    }

    private func save() {
        do {
            let candidate: AutofillSaveCandidate
            switch offer.candidate.kind {
            case .password:
                candidate = .password(try SavedPassword(website: offer.origin, username: username, password: password))
            case .card:
                guard let month = Int(month), let year = Int(year) else { throw AutofillVaultError.invalidData }
                let card = try PaymentCard(number: number, cardholder: cardholder, month: month, year: year, securityCode: securityCode)
                guard !card.isExpired() else { throw AutofillVaultError.invalidData }
                candidate = .card(card)
            case .contact:
                contact.countryCode = contact.countryCode.uppercased()
                guard contact.isValid else { throw AutofillVaultError.invalidData }
                candidate = .contact(contact)
            }
            validation = nil
            Task { await session.save(offer, replacement: candidate) }
        } catch { validation = String(localized: "Check the details and try again.") }
    }
}
