// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

struct DeveloperModeTests {
    @Test(arguments: [
        "http://localhost:5173/?seed=35144",
        "http://app.localhost:3000",
        "http://127.0.0.1:8080",
        "http://[::1]:8000",
        "http://0.0.0.0:4000",
        "https://game.test",
        "http://mac-studio.local:5173",
    ])
    func localHostsStartInDeveloperMode(_ address: String) throws {
        let name = TestDefaults.name("DeveloperModeLocal")
        let suite = try #require(UserDefaults(suiteName: name))
        defer { suite.removePersistentDomain(forName: name) }

        #expect(BrowserSettings(defaults: suite).usesDeveloperMode(for: URL(string: address)))
    }

    @Test(arguments: [
        "https://example.com",
        "http://127.example.com",
        "http://localhost.example.com",
        "file:///Users/me/index.html",
        "linen://settings",
    ])
    func otherAddressesDoNot(_ address: String) throws {
        let name = TestDefaults.name("DeveloperModeRemote")
        let suite = try #require(UserDefaults(suiteName: name))
        defer { suite.removePersistentDomain(forName: name) }

        #expect(!BrowserSettings(defaults: suite).usesDeveloperMode(for: URL(string: address)))
    }

    @Test func aHostChoicePersistsAndOnlyStoresOverrides() throws {
        let name = TestDefaults.name("DeveloperModeOverrides")
        let suite = try #require(UserDefaults(suiteName: name))
        defer { suite.removePersistentDomain(forName: name) }

        let settings = BrowserSettings(defaults: suite)
        let staging = URL(string: "https://staging.example.com/path")
        let local = URL(string: "http://localhost:5173")

        settings.setDeveloperMode(true, for: staging)
        settings.setDeveloperMode(false, for: local)
        let restored = BrowserSettings(defaults: suite)
        #expect(restored.usesDeveloperMode(for: URL(string: "https://staging.example.com/other")))
        #expect(!restored.usesDeveloperMode(for: URL(string: "http://localhost:3000")))

        restored.setDeveloperMode(true, for: local)
        restored.setDeveloperMode(false, for: staging)
        #expect(restored.developerHosts.isEmpty)
        #expect(restored.nonDeveloperHosts.isEmpty)
        #expect(restored.usesDeveloperMode(for: local))
    }
}
