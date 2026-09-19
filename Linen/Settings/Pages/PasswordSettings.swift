// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct PasswordSettings: View {
    @Bindable var settings: BrowserSettings
    let extensions: ExtensionManager
    @State private var model: PasswordSettingsModel
    @State private var editing: SavedPassword?
    @State private var showsAdd = false
    @State private var removing: SavedPassword.Summary?
    @State private var query = ""

    init(settings: BrowserSettings, extensions: ExtensionManager, profileID: UUID) {
        self.settings = settings
        self.extensions = extensions
        _model = State(initialValue: PasswordSettingsModel(profileID: profileID))
    }

    private var provider: InstalledExtension? {
        PasswordExtensionPolicy.provider(in: extensions.installed + extensions.systemExtensions, selectedID: settings.passwordExtensionID)
    }

    private var availableProviders: [InstalledExtension] {
        PasswordExtensionPolicy.availableProviders(in: extensions.installed + extensions.systemExtensions)
    }

    private var selectedProvider: Binding<String> {
        Binding(
            get: { availableProviders.contains { $0.id == settings.passwordExtensionID } ? settings.passwordExtensionID : "" },
            set: { settings.passwordExtensionID = $0 }
        )
    }

    var body: some View {
        SettingsPageHeader(title: "Passwords")
        VStack(alignment: .leading, spacing: SettingsMetrics.headerGap) {
            SettingsCard {
                if let provider {
                    DetailRow(title: "Password filling") {
                        Text("Managed by \(provider.displayName)").foregroundStyle(.secondary)
                    }
                } else {
                    DetailRow(title: "Save and fill passwords", caption: "Save and fill website logins.") {
                        SettingsToggle($settings.fillsPasswords)
                    }
                }
                RowSeparator()
                DetailRow(title: "Password provider") {
                    Picker("Password provider", selection: selectedProvider) {
                        Text("Automatic").tag("")
                        ForEach(availableProviders) { record in
                            Text(record.displayName).tag(record.id)
                        }
                    }.labelsHidden().fixedSize()
                }
            }
            .disabled(model.profileID == Profile.privateID)
            .settingsAnchor("autofill.passwords")
            if provider != nil {
                Text("Your extension handles password autofill.")
                    .lineLimit(1)
                    .font(Theme.Font.label).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 1)
            }
        }
        AutofillSavePromptReset(kind: .password, profileID: model.profileID)
        SettingsSection(title: "Saved passwords", symbol: "key", footnote: "Encrypted passwords; passkeys use macOS.", accessory: {
            HStack(spacing: 10) {
                if model.isLoaded, !model.entries.isEmpty {
                    ToolbarSearchField(query: $query, placeholder: "Search passwords")
                }
                ToolbarChip(symbol: "plus", label: "Add Password") { showsAdd = true }
                    .disabled(!model.isLoaded || model.isBusy || provider != nil)
            }
        }, content: {
            if model.isLoaded {
                if model.entries.isEmpty {
                    SettingsEmptyState(symbol: "key", title: "No saved passwords", caption: "Save a login to see it here.")
                } else if !query.isEmpty, !model.entries.contains(where: {
                    $0.origin.localizedCaseInsensitiveContains(query) || $0.username.localizedCaseInsensitiveContains(query)
                }) {
                    SettingsEmptyState(symbol: "magnifyingglass", title: "No matches", caption: "No passwords match your search.")
                }
                ForEach(model.entries.filter { query.isEmpty || $0.origin.localizedCaseInsensitiveContains(query) || $0.username.localizedCaseInsensitiveContains(query) }) { entry in
                    SiteRow(host: entry.origin, summary: entry.username) {
                        HStack(spacing: 8) {
                            Button("Edit…") { Task { editing = await model.password(entry.id) } }
                                .disabled(provider != nil || model.isBusy)
                            Button("Remove", role: .destructive) { removing = entry }
                                .disabled(model.isBusy)
                        }
                        .buttonStyle(.bordered).fixedSize()
                    }
                }
                AutofillPageStatus(isBusy: model.isBusy, error: model.error, kind: .password)
            } else {
                PasswordSettingsAccess(model: model)
            }
        })
        .task { await model.load() }
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
        .onChange(of: provider?.id) { _, _ in editing = nil; showsAdd = false }
        .sheet(isPresented: $showsAdd) { PasswordEditorSheet(model: model) }
        .sheet(item: $editing) { record in PasswordEditorSheet(model: model, existing: record) }
        .confirmationDialog(
            "Remove Password?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            presenting: removing
        ) { entry in
            Button("Remove Password", role: .destructive) { Task { await model.remove(entry.id) } }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            Text("Remove the saved login for \(entry.origin)?")
        }
    }

    private func lock() {
        model.lock()
        editing = nil
        showsAdd = false
        removing = nil
    }
}

private struct PasswordSettingsAccess: View {
    let model: PasswordSettingsModel

    var body: some View {
        VStack(spacing: 12) {
            if model.isBusy {
                Spinner(size: 22)
                Text("Accessing passwords…").font(Theme.Font.row)
            } else {
                Image(systemName: "lock")
                    .font(.system(size: 26))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text("Passwords are locked").font(Theme.Font.row).fontWeight(.medium)
                if model.profileID == Profile.privateID {
                    Text("Saved passwords are unavailable in Private Browsing.")
                        .font(Theme.Font.label)
                } else {
                    Text(model.error ?? String(localized: "Unlock to view and edit passwords."))
                        .font(Theme.Font.label)
                        .fixedSize(horizontal: false, vertical: true)
                    SettingsButton(title: "Unlock Passwords", isProminent: true) {
                        Task { await model.load() }
                    }
                }
            }
        }
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}

private struct PasswordEditorSheet: View {
    let model: PasswordSettingsModel
    var existing: SavedPassword?
    @Environment(\.dismiss) private var dismiss
    @State private var website = ""
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Login Details").font(.headline)
            Form {
                TextField("Website", text: $website)
                TextField("Username or email", text: $username)
                AutofillPasswordField(password: $password)
                Button("Generate Strong Password") {
                    do { password = try SavedPassword.generate() } catch { self.error = String(localized: "Couldn’t generate a password.") }
                }
            }.textFieldStyle(.roundedBorder)
            if let error = error ?? model.error {
                Text(error).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty || website.isEmpty || model.isBusy)
            }
        }.padding(24).frame(width: 460)
        .onAppear {
            if let existing {
                website = existing.origin
                username = existing.username
                password = existing.password
            }
        }
        .onDisappear { password = "" }
    }

    private func save() {
        do {
            var record = try SavedPassword(website: website, username: username, password: password)
            if let existing {
                record.id = existing.id
            }
            Task { if await model.save(record) { password = ""; dismiss() } }
        } catch {
            self.error = String(localized: "Enter a valid HTTPS website and a password.")
        }
    }
}
