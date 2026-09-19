// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import LocalAuthentication
import Synchronization
import Testing

@testable import Linen

nonisolated final class MemoryAutofillStorage: AutofillSecureStorage {
    private struct State {
        var data: [String: Data] = [:]
    }
    private let state = Mutex(State())

    var itemCount: Int {
        state.withLock { $0.data.count }
    }

    func read(service: String, context: LAContext) throws -> Data? {
        state.withLock { $0.data[service] }
    }

    func write(_ data: Data, service: String, context: LAContext) throws {
        state.withLock { $0.data[service] = data }
    }

    func erase(service: String) throws {
        state.withLock { _ = $0.data.removeValue(forKey: service) }
    }
}

@MainActor
struct SecureAutofillVaultTests {
    @Test func passwordsStayInSecureStorageAndAreIsolatedByProfile() async throws {
        let storage = MemoryAutofillStorage()
        let first = SecureAutofillVault<SavedPassword>(profileID: UUID(), kind: "passwords", reason: "Test", storage: storage)
        let second = SecureAutofillVault<SavedPassword>(profileID: UUID(), kind: "passwords", reason: "Test", storage: storage)
        let record = try SavedPassword(website: "https://example.test", username: "ada", password: "test-secret")
        _ = try await first.update { SavedPassword.merging(record, into: $0) }
        #expect(try await first.records() == [record])
        #expect(try await second.records().isEmpty)
        #expect(storage.itemCount == 1)
        try await first.erase()
        #expect(try await first.records().isEmpty)
    }

    @Test func privateVaultRefusesEveryOperation() async {
        let storage = MemoryAutofillStorage()
        let vault = SecureAutofillVault<SavedPassword>(profileID: Profile.privateID, kind: "passwords", reason: "Test", storage: storage)
        await #expect(throws: AutofillVaultError.self) { try await vault.records() }
        await #expect(throws: AutofillVaultError.self) { try await vault.update { $0 } }
        await #expect(throws: AutofillVaultError.self) { try await vault.erase() }
        #expect(storage.itemCount == 0)
    }

    @Test func credentialMatchingUsesExactHTTPSOriginsAndUpdatesTheSameAccount() throws {
        let record = try SavedPassword(website: "https://EXAMPLE.test:443/login", username: "ada", password: "old")
        #expect(record.origin == "https://example.test")
        #expect(SavedPassword.origin(for: URL(string: "http://example.test")!) == nil)
        #expect(SavedPassword.origin(for: URL(string: "https://user@example.test")!) == nil)
        #expect(SavedPassword.origin(for: URL(string: "https://sub.example.test")!) != record.origin)
        #expect(SavedPassword.origin(for: URL(string: "https://example.test:8443")!) != record.origin)
        let updated = try SavedPassword(website: "example.test/account", username: "ada", password: "new")
        let result = SavedPassword.merging(updated, into: [record])
        #expect(result.count == 1)
        #expect(result[0].id == record.id)
        #expect(result[0].password == "new")
        #expect(throws: AutofillVaultError.self) { try SavedPassword(website: "example.test", username: "ada", password: "") }
    }

    @Test func generatedPasswordsAreLongAndVary() throws {
        let generated = try (0..<20).map { _ in try SavedPassword.generate() }
        #expect(Set(generated).count == generated.count)
        #expect(generated.allSatisfy { $0.count == 24 })
    }

    @Test func enabledPasswordExtensionsTakeOverButDisabledAndUnrelatedExtensionsDoNot() {
        var password = InstalledExtension(id: "nngceckbapebfimnlniiiahkandclblb", displayName: "Bitwarden", version: "1", enabled: true, installedAt: .now)
        let other = InstalledExtension(id: "other", displayName: "Reader", version: "1", enabled: true, installedAt: .now)
        #expect(PasswordExtensionPolicy.provider(in: [other, password])?.id == password.id)
        password.enabled = false
        #expect(PasswordExtensionPolicy.provider(in: [other, password]) == nil)
        #expect(PasswordExtensionPolicy.provider(in: [other, password], selectedID: other.id) == nil)
        let apple = InstalledExtension(id: "system", displayName: "Passwords", version: "1", enabled: true, installedAt: .now)
        #expect(PasswordExtensionPolicy.provider(in: [apple])?.id == apple.id)
        #expect(PasswordExtensionPolicy.availableProviders(in: [other, password, apple]).map(\.id) == [apple.id])
        password.enabled = true
        #expect(PasswordExtensionPolicy.provider(in: [password, apple], selectedID: apple.id)?.id == apple.id)
    }
}
