// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews, .exclusiveExternalApp)
struct AppHandoffTests {
    private func asked(
        for route: String,
        routes: [String: HTTPFixtureServer.Response],
        expectedOrigin: String? = nil
    ) async throws -> URL? {
        let server = try await HTTPFixtureServer.start(routes: routes)
        let (openedURLs, continuation) = AsyncStream<URL>.makeStream(bufferingPolicy: .bufferingNewest(1))
        ExternalApp.requestObserverForTesting = { url, origin in
            #expect(origin == (expectedOrigin ?? SitePermissions.origin(for: try? server.url(route))))
            continuation.yield(url)
        }
        defer {
            ExternalApp.requestObserverForTesting = nil
            continuation.finish()
        }

        let tab = BrowserTab(opensBlank: false)
        defer {
            tab.webView.stopLoading()
            withExtendedLifetime(server) {}
        }
        tab.load(try server.url(route))
        var iterator = openedURLs.makeAsyncIterator()
        return await iterator.next()
    }

    @Test func aScriptedJumpToAnAppIsOffered() async throws {
        let seen = try await asked(for: "/js", routes: [
            "/js": .html("<title>Go</title><script>location.href='slack://open'</script>"),
        ])
        #expect(seen?.scheme == "slack")
    }

    @Test func aJumpFromAFrameIsOfferedToo() async throws {
        let seen = try await asked(for: "/frame", routes: [
            "/frame": .html("<title>Go</title><iframe src='slack://open'></iframe>"),
        ])
        #expect(seen?.scheme == "slack", "a hidden frame is how a sign-in page usually hands back")
    }

    @Test func aRedirectStraightToAnAppIsOffered() async throws {
        let seen = try await asked(for: "/redirect", routes: [
            "/redirect": .redirect(to: URL(string: "slack://open")!),
        ])
        #expect(seen?.scheme == "slack")
    }

    @Test func aLinkToAnAppIsOffered() async throws {
        let seen = try await asked(for: "/link", routes: [
            "/link": .html(
                "<title>Go</title><a id='go' href='slack://open'>go</a>"
                    + "<script>document.getElementById('go').click()</script>"
            ),
        ])
        #expect(seen?.scheme == "slack")
    }

    @Test func aCrossOriginFrameUsesItsOwnOrigin() async throws {
        let frameServer = try await HTTPFixtureServer.start(routes: [
            "/frame": .html("<script>location.href='slack://open'</script>"),
        ])
        let frameURL = try frameServer.url("/frame")
        let seen = try await asked(
            for: "/page",
            routes: ["/page": .html("<iframe src='\(frameURL.absoluteString)'></iframe>")],
            expectedOrigin: SitePermissions.origin(for: frameURL)
        )
        #expect(seen?.scheme == "slack")
        withExtendedLifetime(frameServer) {}
    }

    @Test func aRedirectChainUsesTheWebsiteThatHandsOffToTheApp() async throws {
        let authServer = try await HTTPFixtureServer.start(routes: [
            "/finish": .redirect(to: URL(string: "slack://open")!),
        ])
        let authURL = try authServer.url("/finish")
        let seen = try await asked(
            for: "/start",
            routes: ["/start": .redirect(to: authURL)],
            expectedOrigin: SitePermissions.origin(for: authURL)
        )
        #expect(seen?.scheme == "slack")
        withExtendedLifetime(authServer) {}
    }

    @Test func aRedirectAfterALoadedPageUsesTheAuthorizationWebsite() async throws {
        let authServer = try await HTTPFixtureServer.start(routes: [
            "/finish": .redirect(to: URL(string: "slack://open")!),
        ])
        let authURL = try authServer.url("/finish")
        let seen = try await asked(
            for: "/page",
            routes: ["/page": .html("<script>addEventListener('load', () => location.href='\(authURL.absoluteString)')</script>")],
            expectedOrigin: SitePermissions.origin(for: authURL)
        )
        #expect(seen?.scheme == "slack")
        withExtendedLifetime(authServer) {}
    }

    @Test func aScriptDuringAnotherPageLoadKeepsTheScriptsOrigin() async throws {
        let response = ResponseGate()
        defer { response.open() }
        let waitingServer = try await HTTPFixtureServer.start(routes: [
            "/waiting": .html("<title>Waiting</title>", gate: response),
        ])
        let sourceServer = try await HTTPFixtureServer.start(routes: [
            "/page": .html("<title>Source</title>"),
        ])
        let sourceURL = try sourceServer.url("/page")
        let tab = BrowserTab(opensBlank: false)
        defer {
            tab.webView.stopLoading()
            ExternalApp.requestObserverForTesting = nil
            withExtendedLifetime((sourceServer, waitingServer)) {}
        }
        tab.load(sourceURL)
        try #require(await waitUntil { tab.webView.title == "Source" && !tab.webView.isLoading })
        tab.load(try waitingServer.url("/waiting"))
        try #require(await waitUntil { response.requestCount == 1 })
        var observedOrigin: String?
        ExternalApp.requestObserverForTesting = { _, origin in observedOrigin = origin }
        _ = try await tab.webView.evaluateJavaScript("location.href='slack://open'")
        try #require(await waitUntil { observedOrigin != nil })
        #expect(observedOrigin == SitePermissions.origin(for: sourceURL))
    }
}
