// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// Only the logic around the Keychain. The SecItem calls themselves cannot run
/// here - test builds carry no keychain entitlement - so every case uses a
/// provider id that has no stored item, which makes the keychain leg of each
/// lookup answer "nothing" the same way in CI and on a developer's Mac.
struct CredentialStoreTests {
    private let store: any ProviderCredentialStore = KeychainProviderCredentialStore()

    private static func provider(
        auth: Provider.Auth,
        environmentKey: String? = nil
    ) -> Provider {
        Provider(
            id: "test-\(UUID().uuidString)",
            name: "Test Provider",
            blurb: "",
            symbol: "questionmark",
            baseURL: URL(string: "https://example.invalid/v1"),
            wire: .chatCompletions,
            auth: auth,
            environmentKey: environmentKey
        )
    }

    /// A variable that certainly exists in this process, with a value long
    /// enough to mask.
    private static func liveEnvironmentEntry() throws -> (key: String, value: String) {
        let entry = try #require(
            ProcessInfo.processInfo.environment.first { !$0.key.isEmpty && $0.value.count >= 8 }
        )
        return (entry.key, entry.value)
    }

    @Test func aProviderWithoutAuthNeedsNoKey() {
        let provider = Self.provider(auth: .none, environmentKey: "PATH")
        #expect(store.key(for: provider) == nil)
        #expect(store.isConfigured(provider))
        #expect(store.source(for: provider) == CredentialStore.Source.none)
        #expect(store.masked(for: provider) == nil)
    }

    @Test func aBearerProviderWithNothingAnywhereIsUnconfigured() {
        let provider = Self.provider(auth: .bearer)
        #expect(store.key(for: provider) == nil)
        #expect(!store.isConfigured(provider))
        #expect(store.source(for: provider) == CredentialStore.Source.none)
        #expect(store.masked(for: provider) == nil)
    }

    @Test func anUnsetEnvironmentVariableCountsAsNoKey() {
        let provider = Self.provider(
            auth: .bearer,
            environmentKey: "LINEN_TEST_NEVER_SET_\(UUID().uuidString.prefix(8))"
        )
        #expect(store.key(for: provider) == nil)
        #expect(!store.isConfigured(provider))
        #expect(store.source(for: provider) == CredentialStore.Source.none)
    }

    @Test func theEnvironmentSuppliesTheKeyWhenTheKeychainHasNone() throws {
        let entry = try Self.liveEnvironmentEntry()
        let provider = Self.provider(auth: .bearer, environmentKey: entry.key)
        #expect(store.key(for: provider) == entry.value)
        #expect(store.isConfigured(provider))
        #expect(store.source(for: provider) == .environment(entry.key))
    }

    /// Three characters in, four out: enough to tell two keys apart, never
    /// enough to use one.
    @Test func masksTheActiveKeyToAFingerprint() throws {
        let entry = try Self.liveEnvironmentEntry()
        let provider = Self.provider(auth: .bearer, environmentKey: entry.key)
        let masked = try #require(store.masked(for: provider))
        #expect(masked == "\(entry.value.prefix(3))…\(entry.value.suffix(4))")
        #expect(masked.count == 8)
    }

    @Test func savingABlankKeyClearsRatherThanStores() {
        let provider = Self.provider(auth: .bearer)
        #expect(store.save("   \n\t", for: provider) == nil)
        #expect(store.key(for: provider) == nil)
        #expect(!store.isConfigured(provider))
    }
}
