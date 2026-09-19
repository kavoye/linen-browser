// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Contacts
import SwiftUI

struct ContactAutofillSettings: View {
    @Bindable var settings: BrowserSettings
    @State private var store: AutofillContactStore
    @State private var editing: AutofillContact?
    @State private var removing: AutofillContact?
    @State private var saveError: String?

    init(settings: BrowserSettings, profile: Profile) {
        self.settings = settings
        _store = State(initialValue: AutofillContactStore(profile: profile))
    }

    var body: some View {
        SettingsPageHeader(title: "Contacts and addresses")
        SettingsCard {
            DetailRow(title: "Save and fill contacts and addresses", caption: "Save and fill contact details.") {
                SettingsToggle($settings.fillsContacts)
            }
        }
        .disabled(store.profile.isPrivate)
        .settingsAnchor("autofill.contacts")
        AutofillSavePromptReset(kind: .contact, profileID: store.profile.id)
        SettingsSection(title: "Saved addresses", symbol: "person.crop.rectangle", footnote: "Encrypted contacts; imported copies don’t sync.", accessory: {
            SettingsButton(title: "Add Address", symbol: "plus") { editing = AutofillContact() }
                .disabled(!store.isLoaded || store.isBusy || store.contacts.count >= 100)
        }, content: {
            if store.isLoaded && store.contacts.isEmpty {
                SettingsEmptyState(symbol: "person.crop.rectangle", title: "No saved addresses", caption: "Save an address to fill forms.")
            }
            ForEach(store.contacts) { contact in
                DetailRow(verbatimTitle: contact.title) {
                    HStack(spacing: 8) {
                        Button("Edit…") { editing = contact }
                        Button("Remove", role: .destructive) { removing = contact }
                    }
                    .buttonStyle(.bordered).fixedSize()
                }
            }
            AutofillPageStatus(isBusy: store.isBusy, error: store.error ?? saveError, kind: .contact)
        })
        .task { await store.load() }
        .onDisappear { store.lock(); editing = nil }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.sessionDidResignActiveNotification)) { _ in
            store.lock()
            editing = nil
        }
        .sheet(item: $editing) { contact in
            ContactEditorSheet(contact: contact, store: store)
        }
        .confirmationDialog(
            "Remove Address?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            presenting: removing
        ) { contact in
            Button("Remove Address", role: .destructive) {
                Task { saveError = await store.remove(contact.id) ? nil : String(localized: "Couldn’t remove this address. Try again.") }
            }
            Button("Cancel", role: .cancel) {}
        } message: { contact in
            Text("Remove \(contact.title) from this profile?")
        }
    }
}

private struct ContactEditorSheet: View {
    @State private var contact: AutofillContact
    let store: AutofillContactStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var imported: CNContact?
    @State private var selectedAddress = ""
    @State private var error: String?

    init(contact: AutofillContact, store: AutofillContactStore) {
        _contact = State(initialValue: contact)
        self.store = store
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Contact Details").font(.headline)
            ContactImportButton { selected in
                let id = contact.id
                contact = AutofillContact(contact: selected)
                contact.id = id
                imported = selected
                selectedAddress = selected.isKeyAvailable(CNContactPostalAddressesKey)
                    ? selected.postalAddresses.first?.identifier ?? "" : ""
            }
            ScrollView {
                Form {
                    TextField("Label (for example, Home)", text: $contact.label)
                    TextField("First name", text: $contact.givenName)
                    TextField("Last name", text: $contact.familyName)
                    TextField("Company", text: $contact.organization)
                    TextField("Email", text: $contact.email)
                    TextField("Phone", text: $contact.phone)
                    if let imported {
                        ImportedContactChoices(contact: imported, draft: $contact, selectedAddress: $selectedAddress)
                    }
                    TextField("Street address", text: $contact.street, axis: .vertical).lineLimit(2...3)
                    TextField("City", text: $contact.city)
                    TextField("State or region", text: $contact.region)
                    TextField("Postal code", text: $contact.postalCode)
                    Picker("Country or region", selection: $contact.countryCode) {
                        Text("Not specified").tag("")
                        ForEach(countries, id: \.code) { country in
                            Text(country.name).tag(country.code)
                        }
                    }
                }
                .textFieldStyle(.roundedBorder)
            }
            Text("Sites get an address only when you choose it.")
                .lineLimit(1)
                .font(Theme.Font.caption).foregroundStyle(.secondary)
            if let error {
                Text(error).font(Theme.Font.secondary).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    Task {
                        if await store.save(contact) { dismiss() } else { error = String(localized: "Couldn’t save these details. Try again.") }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!contact.isValid || store.isBusy)
            }
        }
        .padding(24).frame(width: 500, height: 620)
    }

    private var countries: [(code: String, name: String)] {
        Locale.Region.isoRegions.map { region in
            (code: region.identifier, name: locale.localizedString(forRegionCode: region.identifier) ?? region.identifier)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

private struct ImportedContactChoices: View {
    let contact: CNContact
    @Binding var draft: AutofillContact
    @Binding var selectedAddress: String

    var body: some View {
        if contact.isKeyAvailable(CNContactEmailAddressesKey), contact.emailAddresses.count > 1 {
            Picker("Email from Contacts", selection: $draft.email) {
                Text(draft.email).tag(draft.email)
                ForEach(contact.emailAddresses.filter { $0.value as String != draft.email }, id: \.identifier) { value in
                    Text(value.value as String).tag(value.value as String)
                }
            }
        }
        if contact.isKeyAvailable(CNContactPhoneNumbersKey), contact.phoneNumbers.count > 1 {
            Picker("Phone from Contacts", selection: $draft.phone) {
                Text(draft.phone).tag(draft.phone)
                ForEach(contact.phoneNumbers.filter { $0.value.stringValue != draft.phone }, id: \.identifier) { value in
                    Text(value.value.stringValue).tag(value.value.stringValue)
                }
            }
        }
        if contact.isKeyAvailable(CNContactPostalAddressesKey), contact.postalAddresses.count > 1 {
            Picker("Address from Contacts", selection: $selectedAddress) {
                ForEach(contact.postalAddresses, id: \.identifier) { value in
                    Text(CNPostalAddressFormatter.string(from: value.value, style: .mailingAddress)).tag(value.identifier)
                }
            }
            .onChange(of: selectedAddress) { _, id in
                if let address = contact.postalAddresses.first(where: { $0.identifier == id }) {
                    draft.apply(address.value)
                }
            }
        }
    }
}
