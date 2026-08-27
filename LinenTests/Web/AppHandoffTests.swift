// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews, .exclusiveExternalApp)
struct AppHandoffTests {
    private func asked(for route: String, routes: [String: HTTPFixtureServer.Response]) async throws -> URL? {
        let server = try await HTTPFixtureServer.start(routes: routes)
        var seen: URL?
        ExternalApp.openerForTesting = { seen = $0 }
        defer { ExternalApp.openerForTesting = nil }

        let tab = BrowserTab(opensBlank: false)
        tab.load(try server.url(route))
        _ = await waitUntil { seen != nil }
        _ = server
        return seen
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
}
