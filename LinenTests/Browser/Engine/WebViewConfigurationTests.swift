// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Testing
import WebKit

@testable import Linen

@MainActor
struct WebViewConfigurationTests {
    @Test(.boundedWebViews) func configurationsSurviveOtherViewsBeingReleased() async throws {
        let survivor = WKWebView(frame: .zero, configuration: WebViewPool.makeConfiguration())
        weak var released: WKWebView?
        do {
            let temporary = WKWebView(frame: .zero, configuration: WebViewPool.makeConfiguration())
            released = temporary
            temporary.loadHTMLString("<title>Temporary</title>", baseURL: nil)
            try #require(await waitUntil { !temporary.isLoading && temporary.title == "Temporary" })
        }
        try #require(await waitUntil { released == nil })
        survivor.loadHTMLString("<title>Survivor</title>", baseURL: nil)
        try #require(await waitUntil { !survivor.isLoading && survivor.title == "Survivor" })
    }

    /// A shallow copy hands out the template's own preferences, which would
    /// make one tab's settings every tab's.
    @Test func aConfigurationKeepsItsOwnPreferences() {
        let first = WebViewPool.makeConfiguration()
        let second = WebViewPool.makeConfiguration()

        #expect(first.preferences !== second.preferences)
        #expect(first.defaultWebpagePreferences !== second.defaultWebpagePreferences)
    }

    @Test(.boundedWebViews) func pagesSeeOnlySystemAndWebFonts() throws {
        let view = WebViewPool.shared.makeColdView()
        let allowed = try #require(view.configuration.preferences.value(forKey: "shouldAllowUserInstalledFonts") as? Bool)

        #expect(!allowed)
    }

    @Test(.boundedWebViews) func tabsAskWebKitToAddCanvasNoise() throws {
        func policy(_ view: WKWebView) throws -> UInt {
            try #require(view.configuration.defaultWebpagePreferences.value(forKey: "_networkConnectionIntegrityPolicy") as? UInt)
        }
        let tab = WebViewPool.shared.makeColdView()
        let plain = WKWebView(frame: .zero, configuration: WebViewPool.makeConfiguration())

        #expect(try policy(tab) & (1 << 6) != 0)
        #expect(try policy(plain) & (1 << 6) == 0)
    }

    @Test(.boundedWebViews) func pagesReadBackANoisyCanvas() async throws {
        let tab = WebViewPool.shared.makeColdView()
        let plain = WKWebView(frame: .zero, configuration: WebViewPool.makeConfiguration())

        let protected = try await canvasReadback(in: tab)
        let exact = try await canvasReadback(in: plain)

        #expect(protected != exact)
    }

    @Test(.boundedWebViews) func plainHTTPAddressesTryHTTPSFirst() {
        let view = WebViewPool.shared.makeColdView()

        #expect(view.configuration.defaultWebpagePreferences.preferredHTTPSNavigationPolicy == .automaticFallbackToHTTP)
    }

    @Test(.boundedWebViews) func onlyPrivateTabsDropClickIDs() async throws {
        let server = try await HTTPFixtureServer.start(routes: ["/landing": .html("<title>Landing</title>")])
        let address = try server.url("/landing?gclid=abc&fbclid=def&utm_source=news")
        let privateTab = BrowserProfileContext.shared(for: .privateBrowsing()).webViewPool.makeColdView()
        let regularTab = WebViewPool.shared.makeColdView()

        for tab in [privateTab, regularTab] {
            tab.load(URLRequest(url: address))
            try #require(await waitUntil { !tab.isLoading && tab.title == "Landing" })
        }

        #expect(privateTab.url?.query == "utm_source=news")
        #expect(regularTab.url?.query == "gclid=abc&fbclid=def&utm_source=news")
    }

    @Test(.boundedWebViews) func aLoadedTabLeavesAProcessReadyForTheNext() async throws {
        let server = try await HTTPFixtureServer.start(routes: ["/first": .html("<title>First</title>")])
        let model = BrowserModel(
            database: .temporary(),
            sitePermissions: SitePermissions(
                storageURL: TestFiles.directory.appendingPathComponent("Prewarm-\(UUID().uuidString).json")
            )
        )
        let tab = model.newTab(url: try server.url("/first"))
        try #require(await waitUntil { !tab.webView.isLoading && tab.webView.title == "First" })

        let pool = try #require(tab.webView.configuration.value(forKey: "processPool") as? NSObject)
        #expect(await waitUntil(timeout: .seconds(5)) {
            pool.value(forKey: "_hasPrewarmedWebProcess") as? Bool == true
        })
    }

    private func canvasReadback(in view: WKWebView) async throws -> String {
        view.loadHTMLString("<title>Canvas</title>", baseURL: URL(string: "https://example.com/"))
        try #require(await waitUntil { !view.isLoading && view.title == "Canvas" })
        let readback = try await view.callAsyncJavaScript(
            """
            const canvas = document.createElement('canvas');
            canvas.width = 240;
            canvas.height = 60;
            const context = canvas.getContext('2d');
            context.font = '16px Helvetica';
            context.fillStyle = '#123';
            context.fillText('Linen canvas readback', 4, 30);
            return canvas.toDataURL();
            """,
            contentWorld: .page
        )
        return try #require(readback as? String)
    }

    @Test func turningJavaScriptOffForOnePageLeavesTheOthersAlone() {
        let first = WebViewPool.makeConfiguration()
        let second = WebViewPool.makeConfiguration()

        first.defaultWebpagePreferences.allowsContentJavaScript = false

        #expect(second.defaultWebpagePreferences.allowsContentJavaScript)
    }

    @Test(.boundedWebViews) func theLinkPreviewLeavesEveryTabsSettingsAlone() {
        let settings = BrowserSettings.shared
        let wasEnabled = settings.javaScriptEnabled
        settings.javaScriptEnabled = false
        defer { settings.javaScriptEnabled = wasEnabled }

        let tab = WebViewPool.shared.makeColdView()
        _ = LinkPeekLoader.configuration()

        #expect(
            !tab.configuration.defaultWebpagePreferences.allowsContentJavaScript,
            "the tab keeps the setting it was built with"
        )
    }

    /// A user script belongs to the page it was put in. The copy shares its
    /// content controller, so every configuration takes a fresh one.
    @Test func aScriptInOneConfigurationStaysThere() {
        let first = WebViewPool.makeConfiguration()
        let second = WebViewPool.makeConfiguration()

        first.userContentController.addUserScript(WKUserScript(
            source: "void 0",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        #expect(!second.userContentController.userScripts.contains { $0.source == "void 0" })
        #expect(second.userContentController.userScripts.contains { $0.source == PageFrameRegistry.script })
    }

    @Test(.boundedWebViews) func aBuiltViewKeepsItsOwnPreferences() {
        let first = WebViewPool.shared.makeColdView()
        let second = WebViewPool.shared.makeColdView()

        #expect(first.configuration.preferences !== second.configuration.preferences)
    }
}
