// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

enum AutofillDestination: String {
    case passwords, cards, contacts

    init?(anchor: String?) {
        guard let anchor else { return nil }
        self.init(rawValue: anchor == "autofill.applePay" ? "cards" : anchor.replacingOccurrences(of: "autofill.", with: ""))
    }
}

struct AutofillSettings: View {
    let coordinator: AppCoordinator
    @Bindable var settings: BrowserSettings
    var highlight: String?
    @State private var destination: AutofillDestination?

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            if let destination {
                SubPageHeader(backTitle: "Autofill", onBack: { self.destination = nil }) {}
                switch destination {
                case .passwords:
                    PasswordSettings(settings: settings, extensions: coordinator.extensions, profileID: coordinator.profiles.current.id)
                case .cards:
                    PaymentCardSettings(settings: settings, profileID: coordinator.profiles.current.id)
                case .contacts:
                    ContactAutofillSettings(settings: settings, profile: coordinator.profiles.current)
                }
            } else {
                SettingsPageHeader(title: "Autofill", caption: "Linen stores saved details on this Mac.")
                SettingsCard {
                    DrillInRow(title: "Passwords", symbol: "key", tint: .orange, caption: "Save and fill website logins.") { destination = .passwords }
                    RowSeparator()
                    DrillInRow(title: "Payment cards", symbol: "creditcard", tint: .blue, caption: "Save and fill payment cards.") { destination = .cards }
                    RowSeparator()
                    DrillInRow(title: "Contacts and addresses", symbol: "person.crop.rectangle", tint: .green, caption: "Save and fill contact details.") { destination = .contacts }
                }
            }
        }
        .environment(\.settingsDescriptionLineLimit, 1)
        .id(coordinator.profiles.current.id)
        .onChange(of: highlight, initial: true) { _, anchor in
            if let target = AutofillDestination(anchor: anchor) {
                destination = target
            }
        }
    }
}

struct AutofillPageStatus: View {
    let isBusy: Bool
    let error: String?
    let kind: AutofillSaveKind

    private var loadingMessage: LocalizedStringResource {
        switch kind {
        case .password:
            "Accessing passwords…"
        case .card:
            "Accessing cards…"
        case .contact:
            "Accessing addresses…"
        }
    }

    var body: some View {
        if isBusy {
            HStack(spacing: 8) {
                Spinner(size: 14)
                Text(loadingMessage).foregroundStyle(.secondary)
            }.padding(.vertical, 12)
        }
        if let error {
            Text(verbatim: error).foregroundStyle(.secondary).font(Theme.Font.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 12)
        }
    }
}
