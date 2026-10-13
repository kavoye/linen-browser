// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
private func isolatedSystemTab() -> BrowserTab {
    let configuration = WebViewPool.makeConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.setURLSchemeHandler(SystemPageSchemeHandler(), forURLScheme: SystemPages.scheme)
    let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
    return BrowserTab(adopting: view, opensBlank: false)
}

@MainActor
@Suite(.serialized, .boundedWebViews)
struct SystemPageReachTests {
    private final class PolicyObserver: NSObject, WKNavigationDelegate {
        let delegate: TabNavigationDelegate
        var decision: WKNavigationActionPolicy?

        init(delegate: TabNavigationDelegate) {
            self.delegate = delegate
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            delegate.webView(webView, decidePolicyFor: navigationAction) { policy in
                self.decision = policy
                decisionHandler(policy)
            }
        }
    }

    private func expectRefused(_ script: String, in tab: BrowserTab) async throws {
        let delegate = try #require(tab.webView.navigationDelegate as? TabNavigationDelegate)
        let observer = PolicyObserver(delegate: delegate)
        tab.webView.navigationDelegate = observer
        defer { tab.webView.navigationDelegate = delegate }
        _ = try await tab.webView.evaluateJavaScript(script)
        try #require(await waitUntil { observer.decision != nil })
        #expect(observer.decision == .cancel)
    }

    @Test func aWebsiteCannotSendTheTabToASystemPage() async throws {
        let server = try await HTTPFixtureServer.start(routes: [
            "/": .html("<title>Site</title><a id=\"go\" href=\"linen://settings\">go</a>"),
        ])
        defer { withExtendedLifetime(server) {} }
        let page = try server.url()
        let tab = isolatedSystemTab()
        tab.load(page)
        try #require(await settled(tab, at: page))

        try await expectRefused("location.href = 'linen://settings'", in: tab)

        #expect(tab.internalPage == nil, "a website reached one of Linen's own pages")
        #expect(tab.committedURL == page, "the tab left the website it was on")
    }

    @Test func aLinkToASystemPageIsRefusedToo() async throws {
        let server = try await HTTPFixtureServer.start(routes: [
            "/": .html("<title>Site</title><a id=\"go\" href=\"linen://history\">go</a>"),
        ])
        defer { withExtendedLifetime(server) {} }
        let page = try server.url()
        let tab = isolatedSystemTab()
        tab.load(page)
        try #require(await settled(tab, at: page))

        try await expectRefused("document.getElementById('go').click()", in: tab)

        #expect(tab.internalPage == nil)
        #expect(tab.committedURL == page)
    }

    /// The permit is for one address, not a standing pass: a real load must
    /// not leave the next website able to walk in behind it.
    @Test func askingForAWebsiteWithdrawsThePermit() async throws {
        let server = try await HTTPFixtureServer.start(routes: [
            "/": .html("<title>Site</title>"),
        ])
        defer { withExtendedLifetime(server) {} }
        let page = try server.url()
        let tab = isolatedSystemTab()
        tab.load(BrowserTab.InternalPage.history.url)
        try #require(await settled(tab, at: BrowserTab.InternalPage.history.url))

        tab.load(page)
        try #require(await settled(tab, at: page))

        try await expectRefused("location.href = 'linen://settings'", in: tab)

        #expect(tab.internalPage == nil)
    }

    /// Refusing the web must not refuse the user: Back still walks onto a
    /// system page that is already in the tab's own history.
    @Test func backOntoASystemPageIsStillAllowed() async throws {
        let server = try await HTTPFixtureServer.start(routes: [
            "/": .html("<title>Site</title>"),
        ])
        defer { withExtendedLifetime(server) {} }
        let page = try server.url()
        let tab = isolatedSystemTab()
        tab.load(BrowserTab.InternalPage.history.url)
        try #require(await settled(tab, at: BrowserTab.InternalPage.history.url))
        tab.load(page)
        try #require(await settled(tab, at: page))

        tab.goBack()

        try #require(await settled(tab, at: BrowserTab.InternalPage.history.url))
        #expect(tab.internalPage == .history)
    }
}

/// The scheme answers for the pages that exist and nothing else, so a typo in
/// the address bar fails the load instead of showing a page with nothing on it.
@MainActor
@Suite(.serialized, .boundedWebViews)
struct SystemPageAddressTests {
    @Test func onlyTheRealPagesHaveAnAddress() {
        #expect(SystemPages.names(SystemPages.start))
        for page in BrowserTab.InternalPage.allCases {
            #expect(SystemPages.names(page.url))
            #expect(SystemPages.names(SystemPages.settingsURL(.extensions)))
        }
        #expect(!SystemPages.names(URL(string: "linen://nonsense")))
        #expect(!SystemPages.names(URL(string: "https://example.com")))
        #expect(!SystemPages.names(nil))
    }

    @Test func anAddressThatNamesNoPageDoesNotOpenOne() async {
        let tab = isolatedSystemTab()
        tab.load(URL(string: "linen://nonsense")!)
        await PageSettle.untilQuiet(tab.webView, ceiling: .milliseconds(600))

        #expect(tab.internalPage == nil)
        #expect(!tab.isShowingStartPage)
    }
}
