// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation
import Security

@Observable
final class PasswordSettingsModel {
    let profileID: UUID
    private(set) var entries: [SavedPassword.Summary] = []
    private(set) var isLoaded = false
    private(set) var isBusy = false
    var error: String?
    @ObservationIgnored private let vault: SecureAutofillVault<SavedPassword>
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var authentication: AutofillAuthenticationSession?

    init(profileID: UUID) {
        self.profileID = profileID
        vault = AutofillVaults.passwords(for: profileID)
    }

    func load() async {
        guard !isBusy, !isLoaded, profileID != Profile.privateID else { return }
        isBusy = true
        error = nil
        let revision = revision
        defer { isBusy = false }
        let authentication = await vault.makeAuthenticationSession()
        guard self.revision == revision else { authentication.invalidate(); return }
        self.authentication?.invalidate()
        self.authentication = authentication
        do {
            let entries = try await vault.records(using: authentication).map(\.summary)
            guard self.revision == revision else { return }
            self.entries = entries
            isLoaded = true
            error = nil
        } catch {
            guard self.revision == revision else { return }
            authentication.invalidate()
            self.authentication = nil
            self.error = message(error)
        }
    }

    func lock() {
        revision += 1
        authentication?.invalidate()
        authentication = nil
        entries = []
        isLoaded = false
        error = nil
    }

    func password(_ id: UUID) async -> SavedPassword? {
        guard isLoaded, !isBusy, let authentication else { return nil }
        isBusy = true
        let revision = revision
        defer { isBusy = false }
        do {
            let record = try await vault.records(using: authentication).first { $0.id == id }
            return self.revision == revision ? record : nil
        } catch {
            guard self.revision == revision else { return nil }
            self.error = message(error)
            return nil
        }
    }

    func save(_ record: SavedPassword) async -> Bool {
        await change { SavedPassword.merging(record, into: $0) }
    }

    func remove(_ id: UUID) async {
        _ = await change { $0.filter { $0.id != id } }
    }

    private func change(_ transform: @escaping @Sendable ([SavedPassword]) -> [SavedPassword]) async -> Bool {
        guard !isBusy, isLoaded, profileID != Profile.privateID, let authentication else { return false }
        isBusy = true
        let revision = revision
        defer { isBusy = false }
        do {
            let entries = try await vault.update(using: authentication, transform).map(\.summary)
            guard self.revision == revision else { return false }
            self.entries = entries
            error = nil
            return true
        } catch {
            guard self.revision == revision else { return false }
            self.error = message(error)
            return false
        }
    }

    private func message(_ error: any Error) -> String? {
        switch error {
        case AutofillVaultError.keychain(let status) where status == errSecUserCanceled:
            nil
        case AutofillVaultError.keychain(let status) where status == errSecAuthFailed:
            String(localized: "Couldn’t unlock passwords. Try again.")
        case AutofillVaultError.invalidData:
            String(localized: "Couldn’t read saved passwords. No passwords were changed.")
        case AutofillVaultError.privateBrowsing:
            String(localized: "Saved passwords are unavailable in Private Browsing.")
        default:
            String(localized: "Couldn’t access passwords. Try again.")
        }
    }
}
