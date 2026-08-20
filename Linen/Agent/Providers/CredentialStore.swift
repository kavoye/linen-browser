// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Security

nonisolated enum CredentialStore {
    private static let service = "com.kavoye.Linen"

    enum Source: Equatable, Sendable {
        case keychain
        case environment(String)
        case none
    }

    private static func account(for provider: Provider) -> String {
        "provider:\(provider.id)"
    }

    static func key(for provider: Provider) -> String? {
        guard provider.needsKey else { return nil }
        if let stored = read(account: account(for: provider)), !stored.isEmpty {
            return stored
        }
        guard let name = provider.environmentKey,
              let value = ProcessInfo.processInfo.environment[name],
              !value.isEmpty
        else { return nil }
        return value
    }

    static func isConfigured(_ provider: Provider) -> Bool {
        provider.needsKey ? key(for: provider) != nil : true
    }

    static func source(for provider: Provider) -> Source {
        guard provider.needsKey else { return .none }
        if let stored = read(account: account(for: provider)), !stored.isEmpty {
            return .keychain
        }
        if let name = provider.environmentKey,
           let value = ProcessInfo.processInfo.environment[name],
           !value.isEmpty {
            return .environment(name)
        }
        return .none
    }

    static func masked(for provider: Provider) -> String? {
        guard let key = key(for: provider), key.count >= 8 else { return nil }
        return key.prefix(3) + "…" + key.suffix(4)
    }

    @discardableResult
    static func save(_ key: String, for provider: Provider) -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            delete(for: provider)
            return nil
        }
        let status = write(trimmed, account: account(for: provider))
        guard status != errSecSuccess else { return nil }
        return SecCopyErrorMessageString(status, nil) as String?
            ?? String(localized: "The Keychain refused to store the key (error \(status)).")
    }

    static func delete(for provider: Provider) {
        delete(account: account(for: provider))
    }

    // MARK: - Keychain

    private static func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    private static func write(_ value: String, account: String) -> OSStatus {
        let data = Data(value.utf8)
        let base = query(account: account)
        let update = SecItemUpdate(
            base as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        guard update == errSecItemNotFound else { return update }

        var insert = base
        insert[kSecValueData as String] = data
        // Deliberately not `...ThisDeviceOnly`, so a restored Mac keeps the key.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(insert as CFDictionary, nil)
    }

    private static func delete(account: String) {
        SecItemDelete(query(account: account) as CFDictionary)
    }

    private static func read(account: String) -> String? {
        copy(query(account: account))
    }

    private static func copy(_ query: [String: Any]) -> String? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
