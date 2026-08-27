// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Testing
import WebKit

@testable import Linen

/// Every view is built from a copy of one template. The copy is what keeps a
/// single process pool alive for the whole run — WebKit traps in
/// `~WebProcessPool` on a pool it destroys — and the copy being shallow is the
/// trap that comes with it.
@MainActor
struct WebViewConfigurationTests {
    @available(macOS, deprecated: 12.0)
    @Test func everyConfigurationSharesOneProcessPool() {
        let first = WebViewPool.makeConfiguration()
        let second = WebViewPool.makeConfiguration()

        #expect(first.processPool === second.processPool)
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

    /// The bug 0.4.0 shipped: the assistant's own page turned JavaScript on
    /// for every tab, because the copy handed every configuration the same
    /// preferences to write on.
    @Test func theAssistantsPageLeavesEveryTabsSettingsAlone() {
        let settings = BrowserSettings.shared
        let wasEnabled = settings.javaScriptEnabled
        settings.javaScriptEnabled = false
        defer { settings.javaScriptEnabled = wasEnabled }

        let tab = WebViewPool.shared.makeColdView()
        _ = AgentToolkit.researchConfiguration(extensionController: nil)

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

        #expect(second.userContentController.userScripts.isEmpty)
    }

    @Test func aBuiltViewKeepsItsOwnPreferences() {
        let first = WebViewPool.shared.makeColdView()
        let second = WebViewPool.shared.makeColdView()

        #expect(first.configuration.preferences !== second.configuration.preferences)
    }
}
