// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

@Observable
final class AutofillContactStore {
    let profile: Profile
    private(set) var contacts: [AutofillContact] = []
    private(set) var error: String?
    private(set) var isBusy = false
    private(set) var isLoaded = false
    @ObservationIgnored private let vault: SecureAutofillVault<AutofillContact>
    @ObservationIgnored private var revision = 0

    init(profile: Profile, vault: SecureAutofillVault<AutofillContact>? = nil) {
        self.profile = profile
        self.vault = vault ?? AutofillVaults.contacts(for: profile.id)
    }

    func load() async {
        guard !isBusy, !profile.isPrivate else { return }
        isBusy = true
        error = nil
        let revision = revision
        defer { isBusy = false }
        do {
            let contacts = try await vault.records()
            guard contacts.allSatisfy(\.isValid), self.revision == revision else { return }
            self.contacts = contacts
            isLoaded = true
        } catch {
            if self.revision == revision {
                self.error = (error as? AutofillVaultError)?.localizedDescription ?? String(localized: "Couldn’t load saved contacts.")
            }
        }
    }

    func lock() {
        revision += 1
        contacts = []
        isLoaded = false
    }

    @discardableResult
    func save(_ contact: AutofillContact) async -> Bool {
        guard contact.isValid else { return false }
        return await change { records in
            var updated = records
            if let index = updated.firstIndex(where: { $0.id == contact.id }) {
                updated[index] = contact
            } else {
                updated.append(contact)
            }
            return updated
        }
    }

    @discardableResult
    func remove(_ id: UUID) async -> Bool {
        await change { $0.filter { $0.id != id } }
    }

    private func change(_ transform: @escaping @Sendable ([AutofillContact]) -> [AutofillContact]) async -> Bool {
        guard !isBusy, isLoaded, !profile.isPrivate else { return false }
        isBusy = true
        let revision = revision
        defer { isBusy = false }
        do {
            let updated = try await vault.update(transform)
            if self.revision == revision {
                contacts = updated
            }
            return true
        } catch {
            self.error = (error as? AutofillVaultError)?.localizedDescription ?? String(localized: "Couldn’t save these details.")
            return false
        }
    }
}
