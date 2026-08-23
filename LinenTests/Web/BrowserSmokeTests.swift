// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import GRDB
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct BrowserSmokeTests {
    private func eventually(
        timeout: Duration = .seconds(5),
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    private func permissions(_ name: String) -> SitePermissions {
        SitePermissions(
            storageURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("\(name)-\(UUID().uuidString).json")
        )
    }

    private func webView(using dataStore: WKWebsiteDataStore) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        return WKWebView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
    }

    @Test func navigationHistoryPermissionsAndAgentHandoffStayConnected() async throws {
        let server = try await HTTPFixtureServer.start(routes: [
            "/first": .html("""
                <title>First fixture</title>
                <h1>First page</h1>
                <a href="/second">Next page</a>
                """),
            "/second": .html("<title>Second fixture</title><h1>Second page</h1>"),
        ])
        let firstURL = try server.url("/first")
        let secondURL = try server.url("/second")
        let permissions = SitePermissions(
            storageURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("BrowserSmoke-\(UUID().uuidString).json")
        )
        let browser = BrowserModel(database: .temporary(), sitePermissions: permissions)
        let tab = browser.newTab(url: firstURL)

        #expect(await PageSettle.untilIdle(tab.webView, timeout: .seconds(30)))
        #expect(await eventually { tab.urlString == firstURL.absoluteString })
        #expect(await eventually { tab.title == "First fixture" })

        tab.assistantAccess.persistsAnswers = false
        tab.assistantAccess.pageChanged(url: firstURL)
        tab.assistantAccess.set(.control)
        let toolkit = AgentToolkit(
            browser: browser,
            media: MediaCenter(),
            log: ConversationLog(database: .temporary())
        )
        toolkit.beginTask(AgentTaskContext(id: UUID(), tabID: tab.id))

        let observation = await toolkit.readPage()
        #expect(observation.contains("First page"))
        #expect(observation.contains(secondURL.absoluteString))

        let click = await toolkit.clickOnPage(ref: 0, label: "Next page")
        #expect(click.contains("Second page"))
        #expect(await eventually { tab.urlString == secondURL.absoluteString && tab.canGoBack })
        #expect(await eventually { tab.title == "Second fixture" })

        let back = await toolkit.goBack()
        #expect(back.contains("First page"))
        #expect(await eventually { tab.urlString == firstURL.absoluteString && tab.canGoForward })

        tab.goForward()
        #expect(await PageSettle.untilIdle(tab.webView, timeout: .seconds(30)))
        #expect(await eventually { tab.urlString == secondURL.absoluteString && tab.canGoBack })
    }

    @Test func relaunchRestoresALiveWebKitHistoryStack() async throws {
        let server = try await HTTPFixtureServer.start(routes: [
            "/one": .html("<title>Restored one</title><h1>One</h1>"),
            "/two": .html("<title>Restored two</title><h1>Two</h1>"),
        ])
        let one = try server.url("/one")
        let two = try server.url("/two")
        let database = AppDatabase.temporary()
        let original = BrowserModel(database: database, sitePermissions: permissions("LaunchSmoke"))
        let tab = original.newTab(url: one)

        #expect(await eventually(timeout: .seconds(10)) { tab.title == "Restored one" })
        tab.load(two)
        #expect(await eventually(timeout: .seconds(10)) {
            tab.urlString == two.absoluteString && tab.title == "Restored two" && tab.canGoBack
        })
        original.saveBlocking()

        let relaunched = BrowserModel(database: database, sitePermissions: permissions("LaunchSmoke"))
        relaunched.restoreSession()
        let restored = try #require(relaunched.tabs.first { $0.id == tab.id })

        #expect(relaunched.activeTabID == restored.id)
        #expect(await eventually(timeout: .seconds(10)) {
            restored.urlString == two.absoluteString
                && restored.title == "Restored two"
                && restored.canGoBack
        })

        restored.goBack()
        #expect(await eventually(timeout: .seconds(10)) {
            restored.urlString == one.absoluteString
                && restored.title == "Restored one"
                && restored.canGoForward
        })
    }

    @Test func aWebKitDownloadReachesItsIsolatedDestination() async throws {
        let payload = Data("fixture download\n".utf8)
        let server = try await HTTPFixtureServer.start(routes: [
            "/file": .download(payload, filename: "fixture.txt"),
        ])
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("linen-download-smoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let downloads = DownloadManager(destinationFolder: folder, asksWhereToSave: false)
        let browser = BrowserModel(
            database: .temporary(),
            sitePermissions: permissions("DownloadSmoke"),
            downloads: downloads
        )
        let tab = browser.newTab(url: try server.url("/file"))

        #expect(await eventually(timeout: .seconds(10)) {
            downloads.items.first?.state == .finished
        })
        let item = try #require(downloads.items.first)
        let destination = try #require(item.destination)

        #expect(item.filename == "fixture.txt")
        #expect(item.sourceTabID == tab.id)
        #expect(destination.deletingLastPathComponent() == folder)
        #expect(try Data(contentsOf: destination) == payload)
    }

    @Test func aFreshPrivateSessionHasNoPriorTabsCookiesOrAgentLog() async throws {
        let server = try await HTTPFixtureServer.start(routes: [
            "/set": .html(
                "<title>Private state</title><h1>Private</h1>",
                headers: ["Set-Cookie": "privateToken=secret; Path=/; SameSite=Lax"]
            ),
            "/read": .html("<title>Fresh private state</title><h1>Fresh</h1>"),
        ])

        do {
            let session = PrivateBrowsingSession()
            let store = permissions("PrivateSmoke")
            let browser = BrowserModel(database: session.database, sitePermissions: store)
            browser.adopt(database: session.database, sitePermissions: store, privately: true)
            let tab = browser.newTab(
                url: try server.url("/set"),
                adopting: webView(using: session.dataStore)
            )

            #expect(await eventually(timeout: .seconds(10)) { tab.title == "Private state" })
            let cookie = try await tab.webView.evaluateJavaScript("document.cookie") as? String
            #expect(cookie?.contains("privateToken=secret") == true)

            let log = ConversationLog(database: session.database)
            let task = log.beginTask("Private request", tabID: tab.id)
            log.completeTask(task, response: "Private response")
            browser.saveBlocking()

            let savedTabs = try await session.database.writer.read { database in
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM sessionTab")
            }
            #expect(savedTabs == 1)
            #expect(!log.traces.isEmpty)
            browser.closeAllTabs()
        }

        let fresh = PrivateBrowsingSession()
        let freshPermissions = permissions("PrivateSmoke")
        let browser = BrowserModel(database: fresh.database, sitePermissions: freshPermissions)
        browser.adopt(database: fresh.database, sitePermissions: freshPermissions, privately: true)
        browser.restoreSession()
        #expect(browser.tabs.isEmpty)
        #expect(ConversationLog(database: fresh.database).traces.isEmpty)

        let tab = browser.newTab(
            url: try server.url("/read"),
            adopting: webView(using: fresh.dataStore)
        )
        #expect(await eventually(timeout: .seconds(10)) { tab.title == "Fresh private state" })
        let cookie = try await tab.webView.evaluateJavaScript("document.cookie") as? String
        #expect(cookie?.isEmpty == true)
    }

    @Test func extensionEnablementLoadsAndUnloadsItsWebKitContext() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("linen-extension-smoke-\(UUID().uuidString)", isDirectory: true)
        let id = "smoke-extension"
        let package = directory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data(
            #"{"manifest_version":3,"name":"Smoke Extension","version":"1.0"}"#.utf8
        ).write(to: package.appendingPathComponent("manifest.json"))
        defer { try? FileManager.default.removeItem(at: directory) }

        let library = ExtensionLibrary(baseDirectory: directory)
        library.recordInstall(id: id)
        let browser = BrowserModel(database: .temporary(), sitePermissions: permissions("ExtensionSmoke"))
        let manager = ExtensionManager(browser: browser, library: library)

        await manager.start()
        #expect(manager.installed.first?.displayName == "Smoke Extension")
        #expect(manager.contexts[id] != nil)

        manager.setEnabled(false, id: id)
        #expect(manager.installed.first?.enabled == false)
        #expect(manager.contexts[id] == nil)
        let disabledLibrary = ExtensionLibrary(baseDirectory: directory)
        disabledLibrary.load()
        #expect(disabledLibrary.records.first?.enabled == false)

        manager.setEnabled(true, id: id)
        #expect(await eventually { manager.contexts[id] != nil })
        #expect(manager.installed.first?.enabled == true)
        let enabledLibrary = ExtensionLibrary(baseDirectory: directory)
        enabledLibrary.load()
        #expect(enabledLibrary.records.first?.enabled == true)

        manager.setEnabled(false, id: id)
    }
}
