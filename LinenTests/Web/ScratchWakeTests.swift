// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct ScratchWakeTests {
    private func window() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
    }

    private func host(_ webView: WKWebView, in window: NSWindow) {
        webView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        window.contentView?.subviews.forEach { $0.removeFromSuperview() }
        window.contentView?.addSubview(webView)
        window.orderBack(nil)
    }

    @Test(arguments: [false, true])
    func wakingADiscardedTabBringsThePageBack(attachBeforeActivate: Bool) async throws {
        let server = try await HTTPFixtureServer.start(routes: [
            "/a": .html("<title>Page A</title><h1>A</h1>"),
            "/b": .html("<title>Page B</title><h1>B</h1>"),
        ])
        let a = try server.url("/a")
        let b = try server.url("/b")
        let permissions = SitePermissions(
            storageURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("Wake-\(UUID().uuidString).json")
        )
        let model = BrowserModel(database: .temporary(), sitePermissions: permissions)
        let sleeper = model.newTab(url: a)
        let keeper = model.newTab(url: b)
        let win = window()
        defer {
            win.orderOut(nil)
            win.contentView?.subviews.forEach { $0.removeFromSuperview() }
            sleeper.detach()
            keeper.detach()
        }
        host(sleeper.webView, in: win)
        #expect(await PageSettle.untilIdle(sleeper.webView, timeout: .seconds(30)))
        #expect(await waitUntil { sleeper.urlString == a.absoluteString })

        model.activate(keeper)
        host(keeper.webView, in: win)
        model.discardBackgroundTabs()
        #expect(sleeper.isDeferred, "the background tab must be asleep for this test to mean anything")

        if attachBeforeActivate {
            host(sleeper.webView, in: win)
            model.activate(sleeper)
        } else {
            model.activate(sleeper)
            host(sleeper.webView, in: win)
        }

        let woke = await waitUntil(timeout: .seconds(15)) {
            sleeper.webView.url?.absoluteString == a.absoluteString
        }
        #expect(woke, "the woken tab never loaded its page back (url = \(sleeper.webView.url?.absoluteString ?? "nil"))")
        #expect(await waitUntil { sleeper.hasPresentedContent }, "the woken tab never painted")
    }
}
