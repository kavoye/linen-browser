// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct LinkWindowTests {
    private func withProfile(_ action: (BrowserApplication, Profile) throws -> Void) async throws {
        let app = BrowserApplication()
        let catalog = ProfileStore.shared
        let originalSelection = catalog.current
        let profile = catalog.add(name: "Window links")
        let result = Result { try action(app, profile) }
        app.windows.forEach { $0.closeWindow() }
        await app.clearDataOnQuitIfNeeded()
        await catalog.remove(profile)
        catalog.markCurrent(originalSelection)
        try result.get()
    }

    @Test func aLinkUsesItsSourceProfileAndOpensWithoutAnExtraStartPage() async throws {
        try await withProfile { app, profile in
            let source = app.newWindow(profile: profile, show: false)
            let other = app.newWindow(profile: .original(), show: false)
            app.focus(other)
            #expect(source.profiles.current == profile)
            let tab = try #require(source.browser.activeTab)
            let view = try #require(tab.webView as? TabWebView)
            let url = try #require(URL(string: "about:blank#new-window"))

            view.onOpenLinkInNewWindow?(url, false)

            let opened = try #require(app.windows.last)
            #expect(opened !== source && opened !== other)
            #expect(opened.browser.context === source.browser.context)
            #expect(opened.browser.tabs.count == 1)
            #expect(opened.browser.activeTab?.urlString == url.absoluteString)
            #expect(source.browser.activeTab === tab)
            #expect(source.browser.tabs.count == 1)
        }
    }

    @Test func privateLinkWindowsAreIndependentAndRetainTheirSettingsOwner() async throws {
        try await withProfile { app, profile in
            let source = app.newWindow(profile: profile, show: false)
            let url = try #require(URL(string: "about:blank#private-link"))
            let first = try #require(source.openLinkInNewWindow(url, isPrivate: true))
            // An ordinary link-window request from a private source must stay private.
            let second = try #require(first.openLinkInNewWindow(url))

            #expect(first.profiles.isPrivate && second.profiles.isPrivate)
            #expect(first.profiles.profileToReturnTo == profile)
            #expect(second.profiles.profileToReturnTo == profile)
            #expect(first.browser.context !== second.browser.context)
            #expect(first.browser.context.dataStore !== second.browser.context.dataStore)
            #expect(!first.browser.context.dataStore.isPersistent)
            #expect(first.browser.tabs.count == 1 && second.browser.tabs.count == 1)
            #expect(second.browser.activeTab?.urlString == url.absoluteString)
            first.closeWindow()
            #expect(first.openLinkInNewWindow(url) == nil)
            #expect(!second.isClosed)
        }
    }

    @Test func suppliedWindowLinksPreserveTheirOrderWithoutAPlaceholder() throws {
        let app = BrowserApplication()
        let urls = try ["about:blank#first", "about:blank#second"].map { try #require(URL(string: $0)) }
        let opened = app.newWindow(profile: .original(), show: false, urls: urls)
        defer { opened.closeWindow() }

        #expect(opened.browser.tabs.map(\.urlString) == urls.map(\.absoluteString))
        #expect(opened.browser.activeTab?.urlString == urls.first?.absoluteString)
    }

    @Test func aMovedPagesWindowActionFollowsItsNewOwnerAndStopsAfterClose() throws {
        let database = AppDatabase.temporary()
        let source = BrowserModel(windowID: UUID(), database: database)
        let destination = BrowserModel(windowID: UUID(), database: database)
        let tab = source.newTab()
        let view = try #require(tab.webView as? TabWebView)
        var sourceRequests = 0
        var destinationRequests = 0
        source.onOpenInNewWindow = { _, _, _ in sourceRequests += 1 }
        destination.onOpenInNewWindow = { openedFrom, _, privately in
            #expect(openedFrom === tab)
            #expect(privately)
            destinationRequests += 1
        }
        let url = try #require(URL(string: "about:blank#transferred"))
        #expect(destination.adoptTab(tab, from: source))
        view.onOpenLinkInNewWindow?(url, true)
        #expect(sourceRequests == 0)
        #expect(destinationRequests == 1)

        let staleCallback = view.onOpenLinkInNewWindow
        destination.close(tab)
        staleCallback?(url, true)
        #expect(view.onOpenLinkInNewWindow == nil)
        #expect(destinationRequests == 1)
    }
}
