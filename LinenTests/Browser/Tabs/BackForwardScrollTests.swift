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
        defer { withExtendedLifetime(server) {} }
        let tall = try server.url("/tall")
        var other = try server.url("/other")
        if crossHost {
            var components = try #require(URLComponents(url: other, resolvingAgainstBaseURL: false))
            components.host = "localhost"
            other = try #require(components.url)
        }
        let permissions = SitePermissions(
            storageURL: TestFiles.directory
                .appendingPathComponent("BackForwardScroll-\(UUID().uuidString).json")
        )
        let browser = BrowserModel(database: .temporary(), sitePermissions: permissions)
        let tab = browser.newTab(url: tall)
        let host = window(hosting: tab.webView)
        defer {
            host.orderOut(nil)
            browser.close(tab, recordForReopening: false)
        }
        let view = try #require(tab.webView as? TabWebView)
        let onScrollPosition = view.onScrollPosition
        var scrollReports: [String] = []
        view.onScrollPosition = { y, url in
            scrollReports.append("\(url?.absoluteString ?? "nil"): \(y)")
            onScrollPosition?(y, url)
        }

        try #require(await settled(tab, at: tall))

        _ = try await tab.webView.evaluateJavaScript("window.scrollTo(0, 1500)")
        let before = await scrollY(tab.webView)
        try #require(before == 1500)
        // The scroll monitor reports on a short throttle; leaving the page
        // before it fires is not the gesture under test.
        try #require(await waitUntil { tab.lastReportedScrollY == before })

        _ = try await tab.webView.evaluateJavaScript(
            "document.getElementById('next').href = '\(other.absoluteString)'; document.getElementById('next').click()"
        )
        try #require(await settled(tab, at: other))
        try #require(tab.canGoBack)

        tab.goBack()
        try #require(await settled(tab, at: tall))

        let restored = await waitUntil { await scrollY(tab.webView) == before }
        // A transient match misses WebKit resetting the position after our
        // script returns. Check again after the bounded restoration completes.
        let actual = try await tab.webView.callAsyncJavaScript(
            "await new Promise(resolve => setTimeout(resolve, 1400)); return window.scrollY;",
            in: nil, contentWorld: .page
        ) as? Double
        #expect(
            restored && actual == before,
            "Expected \(before), got \(String(describing: actual)); URL: \(tab.urlString); scroll reports: \(scrollReports)"
        )
    }

    /// WebKit can apply its own zero after didFinish and our first restoration.
    /// Reproduce that ordering directly instead of waiting for a process-swap race.
    @Test(.boundedWebViews, arguments: [false, true])
    func restorationSurvivesALateNativeReset(alreadyRestored: Bool) async throws {
        let tab = BrowserTab(opensBlank: false)
        let host = window(hosting: tab.webView)
        defer { host.orderOut(nil) }
        tab.loadHTML("<div style='height: 8000px'>Tall</div>", baseURL: nil)
        try #require(await waitUntil { !tab.webView.isLoading })
        let initial = alreadyRestored ? "window.scrollTo(0, 1500);" : ""
        _ = try await tab.webView.evaluateJavaScript(
            initial + BrowserTab.restoreScrollScript(to: 1500) + "; window.scrollTo(0, 0);"
        )
        #expect(await waitUntil { await scrollY(tab.webView) == 1500 })
    }

    @Test(.boundedWebViews, arguments: ["wheel", "keydown", "pointerdown", "touchstart", "pagehide", "page-scroll"])
    func restorationRespectsSubsequentInput(event: String) async throws {
        let tab = BrowserTab(opensBlank: false)
        let host = window(hosting: tab.webView)
        defer { host.orderOut(nil) }
        tab.loadHTML("<div style='height: 8000px'>Tall</div>", baseURL: nil)
        try #require(await waitUntil { !tab.webView.isLoading })
        let target = event == "page-scroll" ? 700 : 0
        let input = event == "page-scroll" ? "" : "window.dispatchEvent(new Event('\(event)'));"
        let position = try await tab.webView.callAsyncJavaScript(
            BrowserTab.restoreScrollScript(to: 1500) + """
                \(input)
                window.scrollTo(0, \(target));
                await new Promise(resolve => setTimeout(resolve, 1400));
                return window.scrollY;
                """,
            in: nil, contentWorld: .page
        )
        #expect((position as? Double) == Double(target))
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
