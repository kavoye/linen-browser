// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation
import Security

@Observable
final class PaymentCardSettingsModel {
    let profileID: UUID
    private(set) var cards: [PaymentCard.Summary]?
    private(set) var isBusy = false
    var error: String?
    @ObservationIgnored private let vault: PaymentCardVault
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var authentication: AutofillAuthenticationSession?

    init(profileID: UUID) {
        self.profileID = profileID
        vault = AutofillVaults.cards(for: profileID)
    }

    func unlock() async {
        guard !isBusy, cards == nil, profileID != Profile.privateID else { return }
        isBusy = true
        error = nil
        let revision = revision
        defer { isBusy = false }
        do {
            let authentication = try await vault.makeAuthenticationSession()
            guard self.revision == revision else { authentication.invalidate(); return }
            self.authentication?.invalidate()
            self.authentication = authentication
            let cards = try await vault.cards(using: authentication).map(\.summary)
            guard self.revision == revision else { return }
            self.cards = cards
        } catch {
            guard self.revision == revision else { return }
            authentication?.invalidate()
            authentication = nil
            self.error = message(error)
        }
    }

    func add(_ card: PaymentCard) async -> Bool {
        await perform { try await vault.importCards([card], using: $0) }
    }

    func remove(_ id: UUID) async {
        _ = await perform { try await vault.remove(id, using: $0) }
    }

    func lock() {
        revision += 1
        authentication?.invalidate()
        authentication = nil
        cards = nil
        error = nil
    }

    func card(_ id: UUID) async -> PaymentCard? {
        guard cards != nil, !isBusy, let authentication else { return nil }
        isBusy = true
        let revision = revision
        defer { isBusy = false }
        do {
            let card = try await vault.cards(using: authentication).first { $0.id == id }
            return self.revision == revision ? card : nil
        } catch {
            guard self.revision == revision else { return nil }
            self.error = message(error)
            return nil
        }
    }

    private func perform(_ operation: (AutofillAuthenticationSession) async throws -> [PaymentCard.Summary]) async -> Bool {
        guard !isBusy, cards != nil, let authentication else { return false }
        isBusy = true
        error = nil
        let revision = revision
        defer { isBusy = false }
        do {
            guard profileID != Profile.privateID else { throw PaymentCardError.privateBrowsing }
            let cards = try await operation(authentication)
            guard self.revision == revision else { return false }
            self.cards = cards
            return true
        } catch {
            guard self.revision == revision else { return false }
            self.error = message(error)
            return false
        }
    }
    private func message(_ error: any Error) -> String? {
        if case PaymentCardError.keychain(errSecUserCanceled) = error {
            return nil
        }
        return String(localized: "Couldn’t access saved cards. Try again.")
    }
}
