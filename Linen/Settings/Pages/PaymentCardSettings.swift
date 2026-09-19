// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct PaymentCardSettings: View {
    @Bindable var settings: BrowserSettings
    @State private var model: PaymentCardSettingsModel
    @State private var showsAddCard = false
    @State private var editing: PaymentCard?
    @State private var removing: PaymentCard.Summary?

    init(settings: BrowserSettings, profileID: UUID) {
        self.settings = settings
        _model = State(initialValue: PaymentCardSettingsModel(profileID: profileID))
    }

    var body: some View {
        SettingsPageHeader(title: "Payment cards")
        SettingsCard {
            DetailRow(title: "Save and fill payment cards", caption: "Save and fill cards at checkout.") {
                SettingsToggle($settings.fillsPaymentCards)
            }
        }
        .disabled(model.profileID == Profile.privateID)
        .settingsAnchor("autofill.cards")
        AutofillSavePromptReset(kind: .card, profileID: model.profileID)
        SettingsSection(title: "Saved cards", symbol: "creditcard", footnote: "Cards are encrypted in Keychain.", accessory: {
            SettingsButton(title: "Add Card", symbol: "plus") { showsAddCard = true }
                .disabled(model.cards == nil || model.isBusy)
        }, content: {
            if let cards = model.cards {
                if cards.isEmpty {
                    SettingsEmptyState(symbol: "creditcard", title: "No saved cards", caption: "Save a card to use at checkout.")
                }
                ForEach(cards) { card in
                    DetailRow(verbatimTitle: card.label) {
                        HStack(spacing: 8) {
                            Button("Edit…") { Task { editing = await model.card(card.id) } }
                            Button("Remove", role: .destructive) { removing = card }
                        }
                        .buttonStyle(.bordered).fixedSize()
                        .disabled(model.isBusy)
                    }
                }
            } else if !model.isBusy, model.profileID != Profile.privateID {
                VStack(spacing: 12) {
                    Image(systemName: "lock").font(.title2).foregroundStyle(.secondary)
                    Text("Payment cards are locked").font(.headline)
                    Button("Unlock Cards") { Task { await model.unlock() } }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
                .padding(24)
            }
            AutofillPageStatus(isBusy: model.isBusy, error: model.error, kind: .card)
        })
        SettingsSection(title: "Apple Pay", symbol: "apple.logo") {
            DetailRow(title: "Pay with iPhone", caption: "Scan a code to pay with iPhone.") {
                Text("Website support required").foregroundStyle(.secondary).font(Theme.Font.caption)
            }
        }
        .settingsAnchor("autofill.applePay")
        .task { await model.unlock() }
        .onDisappear(perform: lock)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.sessionDidResignActiveNotification)) { _ in
            lock()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
            lock()
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: NSNotification.Name("com.apple.screenIsLocked"))) { _ in
            lock()
        }
        .sheet(isPresented: $showsAddCard) { AddPaymentCardSheet(model: model) }
        .sheet(item: $editing) { card in AddPaymentCardSheet(model: model, existing: card) }
        .confirmationDialog(
            "Remove Card?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            presenting: removing
        ) { card in
            Button("Remove Card", role: .destructive) { Task { await model.remove(card.id) } }
            Button("Cancel", role: .cancel) {}
        } message: { card in
            Text("Remove \(card.label) from this profile?")
        }
    }

    private func lock() {
        model.lock()
        editing = nil
        showsAddCard = false
        removing = nil
    }
}

private struct AddPaymentCardSheet: View {
    let model: PaymentCardSettingsModel
    var existing: PaymentCard?
    @Environment(\.dismiss) private var dismiss
    @State private var number = ""
    @State private var cardholder = ""
    @State private var month = ""
    @State private var year = ""
    @State private var securityCode = ""
    @State private var validation: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(existing == nil ? "Add Payment Card" : "Edit Payment Card").font(.headline)
            Form {
                SecureField("Card number", text: $number)
                TextField("Name on card", text: $cardholder)
                TextField("Expiration month (MM)", text: $month)
                TextField("Expiration year (YYYY)", text: $year)
                SecureField("Security code (optional)", text: $securityCode).privacySensitive()
            }
            .textFieldStyle(.roundedBorder)
            if let message = validation ?? model.error {
                Text(message).font(Theme.Font.secondary).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save Card") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isBusy || number.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear {
            if let existing {
                number = existing.number
                cardholder = existing.cardholder
                month = existing.month.map(String.init) ?? ""
                year = existing.year.map(String.init) ?? ""
                securityCode = existing.securityCode ?? ""
            }
        }
        .onDisappear { number = ""; securityCode = "" }
    }

    private func save() {
        do {
            guard let month = Int(month), let year = Int(year) else { throw PaymentCardError.invalidExpiry }
            var card = try PaymentCard(number: number, cardholder: cardholder, month: month, year: year, securityCode: securityCode)
            if let existing {
                card.id = existing.id
            }
            validation = nil
            Task {
                if await model.add(card) {
                    number = ""
                    securityCode = ""
                    dismiss()
                }
            }
        } catch {
            validation = error.localizedDescription
        }
    }
}
