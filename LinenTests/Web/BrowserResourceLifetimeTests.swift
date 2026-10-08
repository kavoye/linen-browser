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

    @Test func droppingAWindowReleasesItsTabsAndWebViews() async throws {
        weak var releasedBrowser: BrowserModel?
        weak var releasedTab: BrowserTab?
        weak var releasedView: WKWebView?
        do {
            let browser = BrowserModel(database: .temporary())
            let tab = browser.newTab()
            let view = tab.webView
            releasedBrowser = browser
            releasedTab = tab
            releasedView = view
            view.loadHTMLString("<title>Dropped fixture</title>", baseURL: URL(string: "https://fixture.example/"))
            try #require(await waitUntil { !view.isLoading && view.title == "Dropped fixture" })
            browser.cancelPendingSave()
        }
        #expect(await waitUntil { releasedBrowser == nil })
        #expect(await waitUntil { releasedTab == nil })
        #expect(await waitUntil { releasedView == nil })
    }

    @Test func aBackgroundTabWhoseProcessDiesWaitsUntilItIsShown() async throws {
        let browser = BrowserModel(database: .temporary())
        defer { browser.cancelPendingSave() }
        let background = browser.newTab()
        let front = browser.newTab()
        defer {
            browser.close(background, recordForReopening: false)
            browser.close(front, recordForReopening: false)
        }
        let view = background.webView
        view.loadHTMLString("<title>Background fixture</title>", baseURL: URL(string: "https://fixture.example/"))
        try #require(await waitUntil { !view.isLoading && view.title == "Background fixture" })
        background.urlString = "https://fixture.example/"
        try #require(browser.activeTab === front)

        background.contentProcessDidTerminate()

        #expect(!background.isMaterialised)
        #expect(background.isDeferred)

        browser.activate(background)
        #expect(background.isMaterialised)
        #expect(!background.isDeferred)
    }

    @Test func theShownTabReloadsAsSoonAsItsProcessDies() async throws {
        let browser = BrowserModel(database: .temporary())
        defer { browser.cancelPendingSave() }
        let tab = browser.newTab()
        defer { browser.close(tab, recordForReopening: false) }
        let view = tab.webView
        view.loadHTMLString("<title>Front fixture</title>", baseURL: URL(string: "https://fixture.example/"))
        try #require(await waitUntil { !view.isLoading && view.title == "Front fixture" })
        tab.urlString = "https://fixture.example/"
        try #require(browser.activeTab === tab)

        tab.contentProcessDidTerminate()

        #expect(tab.isMaterialised)
        #expect(!tab.isDeferred)
        #expect(tab.webView === view)
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
