// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import LocalAuthentication
import Security

actor PaymentCardVault {
    let profileID: UUID

    init(profileID: UUID) {
        self.profileID = profileID
    }

    func makeAuthenticationSession() throws -> AutofillAuthenticationSession {
        AutofillAuthenticationSession(service: try service(), reason: String(localized: "Access your saved payment cards in Linen."))
    }

    func cards(using session: AutofillAuthenticationSession? = nil) throws -> [PaymentCard] {
        try read(context: context(using: session))
    }

    func importCards(_ incoming: [PaymentCard], preservingMissingSecurityCodes: Bool = false,
                     using session: AutofillAuthenticationSession? = nil) throws -> [PaymentCard.Summary] {
        let context = try context(using: session)
        let cards = PaymentCard.merging(incoming, into: try read(context: context), preservingMissingSecurityCodes: preservingMissingSecurityCodes)
        guard cards.count <= 500 else { throw PaymentCardError.tooLarge }
        try write(cards, context: context)
        return cards.map(\.summary)
    }

    func remove(_ id: UUID, using session: AutofillAuthenticationSession? = nil) throws -> [PaymentCard.Summary] {
        let context = try context(using: session)
        let cards = try read(context: context).filter { $0.id != id }
        try write(cards, context: context)
        return cards.map(\.summary)
    }

    func erase() throws {
        let status = SecItemDelete(try query() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PaymentCardError.keychain(status)
        }
        try? AutofillSaveIndex.replace([], kind: .card, profileID: profileID)
    }

    private func context(using session: AutofillAuthenticationSession?) throws -> LAContext {
        if let session {
            return try session.context(for: service())
        }
        let context = LAContext()
        context.localizedReason = String(localized: "Access your saved payment cards in Linen.")
        return context
    }

    private func service() throws -> String {
        guard profileID != Profile.privateID else { throw PaymentCardError.privateBrowsing }
        var namespace = "com.kavoye.Linen.payment-cards"
        if AppDatabase.isRunningTests {
            namespace += ".tests.\(ProcessInfo.processInfo.processIdentifier)"
        }
        #if DEBUG
        if StageMode.isActive {
            namespace += ".stage"
        }
        #endif
        return "\(namespace).\(profileID.uuidString)"
    }

    private func query() throws -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: try service(),
            kSecAttrAccount as String: "cards",
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    private func read(context: LAContext) throws -> [PaymentCard] {
        var query = try query()
        query[kSecUseAuthenticationContext as String] = context
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw PaymentCardError.keychain(status)
        }
        return try JSONDecoder().decode([PaymentCard].self, from: data)
    }

    private func write(_ cards: [PaymentCard], context: LAContext) throws {
        let data = try JSONEncoder().encode(cards)
        var query = try query()
        query[kSecUseAuthenticationContext as String] = context
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess {
            try? AutofillSaveIndex.replace(cards.map(AutofillSaveCandidate.card), kind: .card, profileID: profileID)
            return
        }
        guard status == errSecItemNotFound else { throw PaymentCardError.keychain(status) }

        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, &error
        ) else {
            throw PaymentCardError.keychain(errSecParam)
        }
        query[kSecAttrAccessControl as String] = access
        query[kSecValueData as String] = data
        let inserted = SecItemAdd(query as CFDictionary, nil)
        guard inserted == errSecSuccess else { throw PaymentCardError.keychain(inserted) }
        try? AutofillSaveIndex.replace(cards.map(AutofillSaveCandidate.card), kind: .card, profileID: profileID)
    }
}
