// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

/// A back within one site is answered by WebKit's page cache; a back across
/// sites swaps WebContent processes and used to come back at the top. The tab
/// remembers where each page was left and puts it back. Both paths are pinned
/// here.
@MainActor
@Suite(.serialized)
struct BackForwardScrollTests {
    private func eventually(
        timeout: Duration = .seconds(10),
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    private func scrollY(_ webView: WKWebView) async -> Double {
        (try? await webView.evaluateJavaScript("window.scrollY")) as? Double ?? -1
    }

    private func window(hosting webView: WKWebView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        webView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        window.contentView?.addSubview(webView)
        window.orderBack(nil)
        return window
    }

    /// crossHost is the case WebKit does not cover: the process swap drops the
    /// page cache, and without the tab's own memory the page lands at the top.
    @Test(.boundedWebViews, arguments: [false, true])
    func goingBackReturnsToTheSpotThePageWasLeftAt(crossHost: Bool) async throws {
        let server = try await HTTPFixtureServer.start(routes: [
            "/tall": .html("""
                <title>Tall</title>
                <div style="height: 8000px">tall page</div>
                <a id="next" href="/other">next</a>
                """),
            "/other": .html("<title>Other</title><h1>Other</h1>"),
        ])
        let tall = try server.url("/tall")
        var other = try server.url("/other")
        if crossHost {
            var components = try #require(URLComponents(url: other, resolvingAgainstBaseURL: false))
            components.host = "localhost"
            other = try #require(components.url)
        }
        let permissions = SitePermissions(
            storageURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("BackForwardScroll-\(UUID().uuidString).json")
        )
        let browser = BrowserModel(database: .temporary(), sitePermissions: permissions)
        let tab = browser.newTab(url: tall)
        let host = window(hosting: tab.webView)
        defer { host.orderOut(nil) }

        #expect(await PageSettle.untilIdle(tab.webView, timeout: .seconds(30)))
        #expect(await eventually { tab.urlString == tall.absoluteString })

        _ = try? await tab.webView.evaluateJavaScript("window.scrollTo(0, 1500)")
        let before = await scrollY(tab.webView)
        #expect(before == 1500)
        // The scroll monitor reports on a short throttle; leaving the page
        // before it fires is not the gesture under test.
        try? await Task.sleep(for: .milliseconds(300))

        _ = try? await tab.webView.evaluateJavaScript(
            "document.getElementById('next').href = '\(other.absoluteString)'; document.getElementById('next').click()"
        )
        #expect(await eventually { tab.urlString == other.absoluteString && tab.canGoBack })
        #expect(await PageSettle.untilIdle(tab.webView, timeout: .seconds(30)))

        tab.goBack()
        #expect(await eventually { tab.urlString == tall.absoluteString })
        #expect(await PageSettle.untilIdle(tab.webView, timeout: .seconds(30)))

        var after = await scrollY(tab.webView)
        let deadline = ContinuousClock.now + .seconds(4)
        while after != 1500, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
            after = await scrollY(tab.webView)
        }
        #expect(after == 1500)
    }

    // MARK: - The memory itself

    @Test func memoryReturnsWhatWasLeftAndOnlyThat() {
        var memory = ScrollReturnMemory()
        memory.remember(1500, leaving: "https://a.example/page")

        #expect(memory.offset(returningTo: "https://a.example/page") == 1500)
        #expect(memory.offset(returningTo: "https://b.example/") == nil)
        #expect(memory.offset(returningTo: nil) == nil)
    }

    /// A page left at the top has nothing to restore; handing back a zero
    /// would still run a script against pages that place themselves.
    @Test func memoryTreatsTheTopAsNothingToRestore() {
        var memory = ScrollReturnMemory()
        memory.remember(0, leaving: "https://a.example/")
        memory.remember(0.5, leaving: "https://b.example/")

        #expect(memory.offset(returningTo: "https://a.example/") == nil)
        #expect(memory.offset(returningTo: "https://b.example/") == nil)
    }

    /// Leaving the same page twice keeps the newer offset - the user may have
    /// scrolled somewhere else on the return visit.
    @Test func memoryKeepsTheLatestOffsetPerAddress() {
        var memory = ScrollReturnMemory()
        memory.remember(1500, leaving: "https://a.example/")
        memory.remember(320, leaving: "https://a.example/")

        #expect(memory.offset(returningTo: "https://a.example/") == 320)
    }

    @Test func memoryStaysBounded() {
        var memory = ScrollReturnMemory(capacity: 3)
        memory.remember(10, leaving: "https://one.example/")
        memory.remember(20, leaving: "https://two.example/")
        memory.remember(30, leaving: "https://three.example/")
        memory.remember(40, leaving: "https://four.example/")

        #expect(memory.offset(returningTo: "https://four.example/") == 40)
        #expect(memory.offset(returningTo: "https://one.example/") == nil)
    }
}
