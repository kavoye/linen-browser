// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.boundedWebViews)
struct BrowserProfileContextTests {
    @Test func windowsOfOneProfileShareServices() {
        let first = BrowserProfileContext.shared(for: .original())
        let second = BrowserProfileContext.shared(for: .original())

        #expect(first === second)
        #expect(first.dataStore === second.dataStore)
        #expect(first.sitePermissions === second.sitePermissions)
        #expect(first.settings === second.settings)
        #expect(first.modelSettings === second.modelSettings)
        #expect(first.actionPolicy === second.actionPolicy)
    }

    @Test func privateWindowsHaveSeparateEphemeralSessions() {
        let first = BrowserProfileContext.shared(for: .privateBrowsing())
        let second = BrowserProfileContext.shared(for: .privateBrowsing())

        #expect(first !== second)
        #expect(first.dataStore !== second.dataStore)
        #expect(!first.dataStore.isPersistent)
        #expect(!second.dataStore.isPersistent)
        #expect(first.database.isEphemeral)
        #expect(second.database.isEphemeral)
        first.pageZoom.set(1.5, for: "example.com")
        #expect(second.pageZoom.level(for: "example.com") == nil)
        first.sitePermissions.setAutoplay(.block, for: "https://example.com")
        #expect(second.sitePermissions.autoplay(for: "https://example.com") == nil)
        first.actionPolicy.allowAlways(.publication, host: "example.com")
        #expect(!second.actionPolicy.isAlwaysAllowed(.publication, host: "example.com"))
    }

    @Test func deferredTabKeepsItsOriginalPrivateStore() {
        let first = BrowserProfileContext.shared(for: .privateBrowsing())
        let tab = BrowserTab(restoring: true, privately: true,
                             sitePermissions: first.sitePermissions, context: first)
        let second = BrowserProfileContext.shared(for: .privateBrowsing())
        let other = BrowserTab(privately: true, sitePermissions: second.sitePermissions, context: second)
        defer { tab.detach(); other.detach() }

        #expect(tab.webView.configuration.websiteDataStore === first.dataStore)
        #expect(other.webView.configuration.websiteDataStore === second.dataStore)
        #expect(tab.webView.configuration.websiteDataStore !== other.webView.configuration.websiteDataStore)
    }

    @Test func memoryOnlySettingsNeverLoadOrOverwriteSavedSiteData() async throws {
        let file = TestFiles.directory.appendingPathComponent("permissions-\(UUID()).json")
        let saved = Data("existing profile data".utf8)
        try saved.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let permissions = SitePermissions(storageURL: file, persists: false)
        permissions.setAutoplay(.block, for: "https://example.com")
        await permissions.waitForPendingSave()

        #expect(try Data(contentsOf: file) == saved)
        #expect(permissions.autoplay(for: "https://example.com") == .block)
    }

    @Test func aTestProcessNeverReadsTheRealPreferences() {
        let probe = "probe.\(UUID().uuidString)"
        AppDatabase.testDefaults.set(true, forKey: probe)
        defer { AppDatabase.testDefaults.removeObject(forKey: probe) }

        #expect(StageMode.defaults.bool(forKey: probe))
        #expect(ProfileSettingsStore.defaults(for: .original()).bool(forKey: probe))
        #expect(UserDefaults.standard.object(forKey: probe) == nil)

        let work = Profile(id: UUID(), name: "Work", symbol: "briefcase", color: .blue)
        defer { ProfileSettingsStore.forget(work.id) }
        ProfileSettingsStore.defaults(for: work).set(true, forKey: probe)
        #expect(UserDefaults(suiteName: ProfileSettingsStore.suiteName(for: work.id))?.object(forKey: probe) == nil)
    }
}
