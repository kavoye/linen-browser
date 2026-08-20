// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

/// Going back to a `pushState` or fragment entry is a same-document
/// navigation: WebKit turns `isLoading` on and off and sends no navigation
/// delegate callback for it. The tab rebuilt its own loading flag from those
/// callbacks, and every other key it did observe - the address, the title,
/// the back and forward flags - is published while `isLoading` is still true.
/// So the flag latched on: a tab that span forever behind a full-width
/// loading bar, on a GitHub pull request, until the page was reloaded.
@MainActor
@Suite(.serialized, .boundedWebViews)
struct SameDocumentBackTests {
    private func servedTab() async throws -> (tab: BrowserTab, page: URL, server: HTTPFixtureServer) {
        let server = try await HTTPFixtureServer.start(routes: [
            "/pull": .html("<title>Pull request</title><h1>Files changed</h1>"),
        ])
        let page = try server.url("/pull")
        let tab = BrowserTab()
        tab.load(page)
        #expect(await waitUntil { !tab.isLoading && tab.urlString == page.absoluteString })
        return (tab, page, server)
    }

    @Test func goingBackToAPushStateEntryEndsTheLoadingState() async throws {
        let (tab, page, server) = try await servedTab()
        _ = server

        _ = try? await tab.webView.evaluateJavaScript("history.pushState({}, '', '#discussion_r1')")
        #expect(await waitUntil { tab.canGoBack && tab.urlString.hasSuffix("#discussion_r1") })

        tab.goBack()

        #expect(await waitUntil { tab.urlString == page.absoluteString }, "the back never landed")
        #expect(await waitUntil { !tab.isLoading }, "the tab still reports itself loading")
    }

    @Test func goingForwardToAPushStateEntryEndsTheLoadingState() async throws {
        let (tab, page, server) = try await servedTab()
        _ = server

        _ = try? await tab.webView.evaluateJavaScript("history.pushState({}, '', '#discussion_r1')")
        #expect(await waitUntil { tab.canGoBack })
        tab.goBack()
        #expect(await waitUntil { tab.canGoForward && tab.urlString == page.absoluteString })

        tab.goForward()

        #expect(await waitUntil { tab.urlString.hasSuffix("#discussion_r1") }, "the forward never landed")
        #expect(await waitUntil { !tab.isLoading }, "the tab still reports itself loading")
    }
}
