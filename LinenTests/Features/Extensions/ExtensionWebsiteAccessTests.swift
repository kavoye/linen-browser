// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
struct ExtensionWebsiteAccessTests {
    private func makeDirectory() -> URL {
        let directory = TestFiles.directory
            .appendingPathComponent("linen-ext-access-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func library(_ directory: URL, _ profile: Profile = .original()) -> ExtensionLibrary {
        let library = ExtensionLibrary(baseDirectory: directory, profile: profile)
        library.load()
        return library
    }

    private func installEveryWebsiteExtension(id: String, in library: ExtensionLibrary) throws {
        let package = library.packageURL(for: id)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data(#"""
        {"manifest_version":3,"name":"Everywhere","version":"1.0","host_permissions":["<all_urls>"]}
        """#.utf8).write(to: package.appendingPathComponent("manifest.json"))
        library.recordInstall(id: id)
    }

    @Test func theWebsiteDropsSchemePathAndWWW() {
        #expect(ExtensionSiteAccess.website(of: URL(string: "https://www.Example.com/a?b")) == "example.com")
        #expect(ExtensionSiteAccess.website(of: URL(string: "http://news.example.com")) == "news.example.com")
        #expect(ExtensionSiteAccess.website(of: URL(string: "linen://settings")) == nil)
        #expect(ExtensionSiteAccess.website(of: URL(string: "file:///tmp/a.html")) == nil)
    }

    @Test func everyWebsiteHasAPattern() throws {
        for address in ["https://example.com/", "http://192.168.1.1/", "http://[::1]:8080/"] {
            let url = try #require(URL(string: address))
            let host = try #require(ExtensionSiteAccess.website(of: url))
            let pattern = try #require(ExtensionSiteAccess.websitePattern(for: host), "\(host)")
            #expect(pattern.matches(url))
        }
    }

    @Test func aBlockedWebsiteIsKeptPerProfileAndSurvivesReordering() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let work = Profile(id: UUID(), name: "Work", symbol: "person", color: .gray)

        let personal = library(directory)
        personal.recordInstall(id: "first")
        personal.recordInstall(id: "second")
        personal.setBlocked(true, host: "example.com", id: "first")
        personal.move("first", before: nil)

        #expect(library(directory).placement(for: "first").blockedHosts == ["example.com"])
        #expect(library(directory, work).placement(for: "first").blockedHosts.isEmpty)

        personal.setBlocked(false, host: "example.com", id: "first")
        #expect(library(directory).placement(for: "first").blockedHosts.isEmpty)
    }

    @Test func aBlockedWebsiteOverridesTheEveryWebsiteGrant() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = "website-access-test"
        let shared = library(directory)
        try installEveryWebsiteExtension(id: id, in: shared)
        let blocked = try #require(URL(string: "https://www.example.com/page"))
        let subdomain = try #require(URL(string: "https://news.example.com/"))
        let other = try #require(URL(string: "https://example.org/"))

        let manager = ExtensionManager(library: shared)
        let browser = BrowserModel(database: .temporary())
        manager.register(browser: browser)
        defer {
            manager.unregister(browser: browser)
            browser.closeAllTabs(saving: false)
        }
        await manager.start()
        let context = try #require(manager.contexts[id])
        #expect(context.permissionStatus(for: blocked) == .grantedImplicitly)

        manager.setAllowed(false, on: "example.com", id: id)
        #expect(manager.isBlocked(id: id, on: "example.com"))
        #expect(manager.blockingHost(id: id, for: "news.example.com") == "example.com")
        #expect(!manager.isBlocked(id: id, on: "notexample.com"))
        #expect(context.permissionStatus(for: blocked) == .deniedExplicitly)
        #expect(context.permissionStatus(for: subdomain) == .deniedExplicitly)
        #expect(context.permissionStatus(for: other) == .grantedImplicitly)

        manager.setAllowed(true, on: "example.com", id: id)
        #expect(!manager.isBlocked(id: id, on: "example.com"))
        #expect(context.permissionStatus(for: blocked) == .grantedImplicitly)
    }

    private static let countingPage = """
        <script>
        sessionStorage.loads = String(Number(sessionStorage.loads || 0) + 1);
        document.title = "Loads " + sessionStorage.loads;
        </script>
        """

    private func openPage(_ url: URL, in browser: BrowserModel) async -> BrowserTab {
        let tab = browser.newTab(url: url)
        #expect(await PageSettle.untilIdle(tab.webView, timeout: .seconds(30)))
        #expect(await waitUntil { tab.webView.title == "Loads 1" })
        return tab
    }

    private func websiteItem(in menu: NSMenu?) -> NSMenuItem? {
        menu?.items.first { $0.title.hasPrefix("Allow on ") }
    }

    @Test(.boundedWebViews) func theMenuOffersTheWebsiteAndBlocksItWhenTurnedOff() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = "website-access-menu"
        let shared = library(directory)
        try installEveryWebsiteExtension(id: id, in: shared)
        let server = try await HTTPFixtureServer.start(routes: ["/": .html(Self.countingPage)])
        let manager = ExtensionManager(library: shared)
        let browser = BrowserModel(database: .temporary())
        manager.register(browser: browser)
        defer {
            manager.unregister(browser: browser)
            browser.closeAllTabs(saving: false)
        }
        await manager.start()
        _ = await openPage(try server.url(), in: browser)

        let offered = try #require(websiteItem(in: manager.contextMenu(for: id, in: browser)))
        #expect(offered.title == "Allow on 127.0.0.1")
        #expect(offered.state == .on)

        let action = try #require(offered.action)
        #expect(NSApp.sendAction(action, to: offered.target, from: offered))
        #expect(manager.isBlocked(id: id, on: "127.0.0.1"))

        let blocked = try #require(websiteItem(in: manager.contextMenu(for: id, in: browser)))
        #expect(blocked.state == .off)
        #expect(NSApp.sendAction(action, to: blocked.target, from: blocked))
        #expect(!manager.isBlocked(id: id, on: "127.0.0.1"))
    }

    @Test(.boundedWebViews) func theMenuLeavesOutWebsitesTheExtensionNeverAskedFor() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = "website-access-narrow"
        let shared = library(directory)
        let package = shared.packageURL(for: id)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data(#"""
        {"manifest_version":3,"name":"Narrow","version":"1.0","host_permissions":["*://*.twitch.tv/*"]}
        """#.utf8).write(to: package.appendingPathComponent("manifest.json"))
        shared.recordInstall(id: id)
        let server = try await HTTPFixtureServer.start(routes: ["/": .html(Self.countingPage)])
        let manager = ExtensionManager(library: shared)
        let browser = BrowserModel(database: .temporary())
        manager.register(browser: browser)
        defer {
            manager.unregister(browser: browser)
            browser.closeAllTabs(saving: false)
        }
        await manager.start()
        let url = try server.url()
        _ = await openPage(url, in: browser)

        #expect(!manager.requestsAccess(id: id, to: url))
        #expect(websiteItem(in: manager.contextMenu(for: id, in: browser)) == nil)
    }

    @Test(.boundedWebViews) func blockingAWebsiteReloadsOnlyItsTabs() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = "website-access-reload"
        let shared = library(directory)
        try installEveryWebsiteExtension(id: id, in: shared)
        let server = try await HTTPFixtureServer.start(routes: ["/": .html(Self.countingPage)])
        let manager = ExtensionManager(library: shared)
        let browser = BrowserModel(database: .temporary())
        manager.register(browser: browser)
        defer {
            manager.unregister(browser: browser)
            browser.closeAllTabs(saving: false)
        }
        await manager.start()
        let address = try server.url()
        let blocked = await openPage(address, in: browser)
        let elsewhere = await openPage(
            try #require(URL(string: "http://localhost:\(address.port ?? 0)/")),
            in: browser
        )

        manager.setAllowed(false, on: "127.0.0.1", id: id, reloading: browser)

        #expect(await waitUntil { blocked.webView.title == "Loads 2" })
        #expect(elsewhere.webView.title == "Loads 1", "a tab on another website is left alone")
    }

    @Test func aBlockedWebsiteStaysBlockedAfterRelaunch() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = "website-access-relaunch"
        let first = library(directory)
        try installEveryWebsiteExtension(id: id, in: first)
        first.setBlocked(true, host: "example.com", id: id)

        let manager = ExtensionManager(library: library(directory))
        let browser = BrowserModel(database: .temporary())
        manager.register(browser: browser)
        defer {
            manager.unregister(browser: browser)
            browser.closeAllTabs(saving: false)
        }
        await manager.start()
        let context = try #require(manager.contexts[id])
        #expect(context.permissionStatus(for: try #require(URL(string: "https://example.com/"))) == .deniedExplicitly)
        #expect(context.permissionStatus(for: try #require(URL(string: "https://example.org/"))) == .grantedImplicitly)
    }
}
