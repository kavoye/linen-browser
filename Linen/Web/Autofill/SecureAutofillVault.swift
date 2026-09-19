// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import LocalAuthentication
import Security

nonisolated protocol AutofillSecureStorage: Sendable {
    func read(service: String, context: LAContext) throws -> Data?
    func write(_ data: Data, service: String, context: LAContext) throws
    func erase(service: String) throws
}

nonisolated struct AutofillKeychainStorage: AutofillSecureStorage {
    enum Access {
        case userPresence
        case whenUnlocked
    }

    var access: Access = .userPresence

    private var account: String {
        access == .whenUnlocked ? "records.when-unlocked" : "records"
    }

    static func query(service: String, account: String = "records") -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account,
         kSecUseDataProtectionKeychain as String: true,
        ]
    }

    func read(service: String, context: LAContext) throws -> Data? {
        var query = Self.query(service: service, account: account)
        query[kSecUseAuthenticationContext as String] = context
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else { throw AutofillVaultError.keychain(status) }
        return data
    }

    func write(_ data: Data, service: String, context: LAContext) throws {
        var query = Self.query(service: service, account: account)
        query[kSecUseAuthenticationContext as String] = context
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess {
            return
        }
        guard status == errSecItemNotFound else { throw AutofillVaultError.keychain(status) }
        let flags: SecAccessControlCreateFlags = access == .userPresence ? .userPresence : []
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, flags, nil)
        else { throw AutofillVaultError.keychain(errSecParam) }
        query[kSecAttrAccessControl as String] = access
        query[kSecValueData as String] = data
        let added = SecItemAdd(query as CFDictionary, nil)
        guard added == errSecSuccess else { throw AutofillVaultError.keychain(added) }
    }

    func erase(service: String) throws {
        let status = SecItemDelete(Self.query(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AutofillVaultError.keychain(status) }
    }
}

nonisolated enum AutofillVaultError: Error, LocalizedError {
    case keychain(OSStatus)
    case invalidData
    case privateBrowsing

    var errorDescription: String? {
        switch self {
        case .keychain(let status) where status == errSecUserCanceled || status == errSecAuthFailed:
            String(localized: "Authentication was canceled. Open this page again to try again.")
        case .keychain:
            String(localized: "Couldn’t access secure storage. Try again.")
        case .invalidData:
            String(localized: "Couldn’t read these saved details. No data was overwritten.")
        case .privateBrowsing:
            String(localized: "Saved autofill details are unavailable in Private Browsing.")
        }
    }
}

nonisolated final class AutofillAuthenticationSession: @unchecked Sendable {
    private let service: String
    private let context: LAContext

    init(service: String, reason: String) {
        self.service = service
        context = LAContext()
        context.localizedReason = reason
    }

    func context(for service: String) throws -> LAContext {
        guard self.service == service else { throw AutofillVaultError.invalidData }
        return context
    }

    func invalidate() { context.invalidate() }
    deinit { context.invalidate() }
}

actor SecureAutofillVault<Record: Codable & Identifiable & Sendable> where Record.ID == UUID {
    let profileID: UUID
    private let service: String
    private let reason: String
    private let storage: any AutofillSecureStorage
    private let saveKind: AutofillSaveKind?
    private let saveCandidates: (@Sendable ([Record]) -> [AutofillSaveCandidate])?

    init(
        profileID: UUID, kind: String, reason: String,
        storage: any AutofillSecureStorage = AutofillKeychainStorage(),
        saveKind: AutofillSaveKind? = nil,
        saveCandidates: (@Sendable ([Record]) -> [AutofillSaveCandidate])? = nil
    ) {
        self.profileID = profileID
        var namespace = "com.kavoye.Linen.autofill"
        if AppDatabase.isRunningTests { namespace += ".tests.\(ProcessInfo.processInfo.processIdentifier)" }
        #if DEBUG
        if StageMode.isActive { namespace += ".stage" }
        #endif
        service = "\(namespace).\(kind).\(profileID.uuidString)"
        self.reason = reason
        self.storage = storage
        self.saveKind = saveKind
        self.saveCandidates = saveCandidates
    }

    func makeAuthenticationSession() -> AutofillAuthenticationSession {
        AutofillAuthenticationSession(service: service, reason: reason)
    }

    func records(using session: AutofillAuthenticationSession? = nil) throws -> [Record] {
        try read(context: context(using: session))
    }

    @discardableResult
    func update(using session: AutofillAuthenticationSession? = nil,
                _ transform: @Sendable ([Record]) throws -> [Record]) throws -> [Record] {
        let context = try context(using: session)
        let records = try transform(read(context: context))
        try write(records, context: context)
        return records
    }

    func erase() throws {
        guard profileID != Profile.privateID else { throw AutofillVaultError.privateBrowsing }
        try storage.erase(service: service)
        updateSaveIndex([])
    }

    private func context(using session: AutofillAuthenticationSession?) throws -> LAContext {
        if let session {
            return try session.context(for: service)
        }
        let context = LAContext()
        context.localizedReason = reason
        return context
    }

    private func read(context: LAContext) throws -> [Record] {
        guard profileID != Profile.privateID else { throw AutofillVaultError.privateBrowsing }
        guard let data = try storage.read(service: service, context: context) else { return [] }
        guard data.count <= 4_000_000 else { throw AutofillVaultError.invalidData }
        let records = try JSONDecoder().decode([Record].self, from: data)
        guard records.count <= 1000, Set(records.map(\.id)).count == records.count else { throw AutofillVaultError.invalidData }
        return records
    }

    private func write(_ records: [Record], context: LAContext) throws {
        guard profileID != Profile.privateID else { throw AutofillVaultError.privateBrowsing }
        guard records.count <= 1000 else { throw AutofillVaultError.invalidData }
        let data = try JSONEncoder().encode(records)
        guard data.count <= 4_000_000 else { throw AutofillVaultError.invalidData }
        try storage.write(data, service: service, context: context)
        updateSaveIndex(records)
    }

    private func updateSaveIndex(_ records: [Record]) {
        guard let saveKind, let saveCandidates else { return }
        try? AutofillSaveIndex.replace(saveCandidates(records), kind: saveKind, profileID: profileID)
    }
}

enum AutofillVaults {
    private static var cards: [UUID: PaymentCardVault] = [:]

    static func cards(for id: UUID) -> PaymentCardVault {
        if let vault = cards[id] { return vault }
        let vault = PaymentCardVault(profileID: id)
        cards[id] = vault
        return vault
    }

    private static var contacts: [UUID: SecureAutofillVault<AutofillContact>] = [:]
    private static var passwords: [UUID: SecureAutofillVault<SavedPassword>] = [:]

    static func contacts(for id: UUID) -> SecureAutofillVault<AutofillContact> {
        if let vault = contacts[id] {
            return vault
        }
        let vault = SecureAutofillVault<AutofillContact>(
            profileID: id, kind: "contacts", reason: String(localized: "Access your saved contacts in Linen."),
            storage: AutofillKeychainStorage(access: .whenUnlocked),
            saveKind: .contact, saveCandidates: { $0.map(AutofillSaveCandidate.contact) }
        )
        contacts[id] = vault
        return vault
    }

    static func passwords(for id: UUID) -> SecureAutofillVault<SavedPassword> {
        if let vault = passwords[id] {
            return vault
        }
        let vault = SecureAutofillVault<SavedPassword>(
            profileID: id, kind: "passwords", reason: String(localized: "Access your saved passwords in Linen."),
            saveKind: .password, saveCandidates: { $0.map(AutofillSaveCandidate.password) }
        )
        passwords[id] = vault
        return vault
    }
}
