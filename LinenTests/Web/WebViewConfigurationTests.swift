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
