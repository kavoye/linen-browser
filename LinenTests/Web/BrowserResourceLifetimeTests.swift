// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct BrowserResourceLifetimeTests {
    @Test func repeatedTabClosureReleasesTabsAndWebViews() async throws {
        let browser = BrowserModel(database: .temporary())
        defer { browser.cancelPendingSave() }
        for index in 0..<20 {
            weak var releasedTab: BrowserTab?
            weak var releasedView: WKWebView?
            do {
                let tab = browser.newTab()
                let view = tab.webView
                releasedTab = tab
                releasedView = view
                view.loadHTMLString("<title>Resource fixture \(index)</title><p>Static page</p>", baseURL: nil)
                try #require(await waitUntil { !view.isLoading && view.title == "Resource fixture \(index)" })
                browser.close(tab, recordForReopening: false)
            }
            try #require(await waitUntil { releasedTab == nil && releasedView == nil })
        }
        #expect(browser.tabs.isEmpty)
    }

    @Test func discardingContentReleasesTheViewButPreservesTheTab() async throws {
        let browser = BrowserModel(database: .temporary())
        let tab = browser.newTab()
        defer { browser.close(tab, recordForReopening: false); browser.cancelPendingSave() }
        weak var releasedView: WKWebView?
        do {
            let view = tab.webView
            releasedView = view
            view.loadHTMLString("<title>Discard fixture</title>", baseURL: URL(string: "https://fixture.example/"))
            try #require(await waitUntil { !view.isLoading && view.title == "Discard fixture" })
            tab.urlString = "https://fixture.example/"
            try #require(tab.canDiscardWebContent)
            tab.discardWebContent()
        }
        #expect(await waitUntil { releasedView == nil })
        #expect(!tab.isMaterialised)
        #expect(browser.tabs.contains { $0 === tab })
    }
}
