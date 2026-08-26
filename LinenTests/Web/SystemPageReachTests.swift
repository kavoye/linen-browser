// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct SystemPageReachTests {
    @Test func aWebsiteCannotSendTheTabToASystemPage() async throws {
        let server = try await HTTPFixtureServer.start(routes: [
            "/": .html("<title>Site</title><a id=\"go\" href=\"linen://settings\">go</a>"),
        ])
        let page = try server.url()
        let tab = BrowserTab(opensBlank: false)
        tab.load(page)
        #expect(await settled(tab, at: page))

        _ = try? await tab.webView.evaluateJavaScript("location.href = 'linen://settings'")
        await PageSettle.untilQuiet(tab.webView, ceiling: .milliseconds(800))

        #expect(tab.internalPage == nil, "a website reached one of Linen's own pages")
        #expect(tab.committedURL == page, "the tab left the website it was on")
    }

    @Test func aLinkToASystemPageIsRefusedToo() async throws {
        let server = try await HTTPFixtureServer.start(routes: [
            "/": .html("<title>Site</title><a id=\"go\" href=\"linen://history\">go</a>"),
        ])
        let page = try server.url()
        let tab = BrowserTab(opensBlank: false)
        tab.load(page)
        #expect(await settled(tab, at: page))

        _ = try? await tab.webView.evaluateJavaScript("document.getElementById('go').click()")
        await PageSettle.untilQuiet(tab.webView, ceiling: .milliseconds(800))

        #expect(tab.internalPage == nil)
        #expect(tab.committedURL == page)
    }

    /// The permit is for one address, not a standing pass: a real load must
    /// not leave the next website able to walk in behind it.
    @Test func askingForAWebsiteWithdrawsThePermit() async throws {
        let server = try await HTTPFixtureServer.start(routes: [
            "/": .html("<title>Site</title>"),
        ])
        let page = try server.url()
        let tab = BrowserTab(opensBlank: false)
        tab.load(BrowserTab.InternalPage.history.url)
        #expect(await settled(tab, at: BrowserTab.InternalPage.history.url))

        tab.load(page)
        #expect(await settled(tab, at: page))

        _ = try? await tab.webView.evaluateJavaScript("location.href = 'linen://settings'")
        await PageSettle.untilQuiet(tab.webView, ceiling: .milliseconds(800))

        #expect(tab.internalPage == nil)
    }

    /// Refusing the web must not refuse the user: Back still walks onto a
    /// system page that is already in the tab's own history.
    @Test func backOntoASystemPageIsStillAllowed() async throws {
        let server = try await HTTPFixtureServer.start(routes: [
            "/": .html("<title>Site</title>"),
        ])
        let page = try server.url()
        let tab = BrowserTab(opensBlank: false)
        tab.load(BrowserTab.InternalPage.history.url)
        #expect(await settled(tab, at: BrowserTab.InternalPage.history.url))
        tab.load(page)
        #expect(await settled(tab, at: page))

        tab.goBack()

        #expect(await settled(tab, at: BrowserTab.InternalPage.history.url))
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
        let tab = BrowserTab(opensBlank: false)
        tab.load(URL(string: "linen://nonsense")!)
        await PageSettle.untilQuiet(tab.webView, ceiling: .milliseconds(600))

        #expect(tab.internalPage == nil)
        #expect(!tab.isShowingStartPage)
    }
}
