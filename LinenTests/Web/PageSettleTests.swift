// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct PageSettleTests {
    private func makeWebView() -> WKWebView {
        let configuration = WebViewPool.makeConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        return WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), configuration: configuration)
    }

    private static let page = """
    <!doctype html><html><body>
    <h1>Hello</h1><p>Some text the agent could read.</p>
    <a href="https://example.com">A link</a>
    </body></html>
    """

    @Test func waitsForALoadAndThenReturns() async {
        let webView = makeWebView()
        webView.loadHTMLString(Self.page, baseURL: URL(string: "https://example.test/"))
        let started = await waitUntil { webView.isLoading }

        let finished = await PageSettle.untilIdle(webView, timeout: .seconds(30))

        #expect(started)
        #expect(finished)
        #expect(!webView.isLoading)
        let text = (try? await webView.evaluateJavaScript("document.body.textContent")) as? String
        #expect(text?.contains("Hello") == true)
    }

    @Test func returnsAtOnceWhenThereIsNoLoadInFlight() async {
        let webView = makeWebView()
        webView.loadHTMLString(Self.page, baseURL: nil)
        #expect(await PageSettle.untilIdle(webView, timeout: .seconds(30)))

        let clock = TestClock()
        let start = clock.now
        #expect(await PageSettle.untilIdle(webView, clock: clock))
        #expect(clock.now == start)
        #expect(clock.pendingCount == 0)
    }

    @Test func aStaticDOMReturnsWellBeforeTheCeiling() async throws {
        let webView = makeWebView()
        webView.loadHTMLString(Self.page, baseURL: nil)
        #expect(await PageSettle.untilIdle(webView, timeout: .seconds(30)))

        let clock = TestClock()
        let interval = Duration.seconds(1)
        let settling = Task { await PageSettle.untilQuiet(webView, ceiling: interval * 3, interval: interval, clock: clock) }
        defer { settling.cancel() }
        try #require(await waitUntil { clock.pendingCount == 1 })
        clock.advance(by: interval)
        await settling.value
        #expect(clock.pendingCount == 0)
    }

    @Test func aSamplingIntervalCannotCarryTheWaitPastItsCeiling() async throws {
        let webView = makeWebView()
        webView.loadHTMLString(Self.page, baseURL: nil)
        #expect(await PageSettle.untilIdle(webView))
        let clock = TestClock()
        let interval = Duration.seconds(1)
        let ceiling = interval / 2
        let settling = Task { await PageSettle.untilQuiet(webView, ceiling: ceiling, interval: interval, clock: clock) }
        defer { settling.cancel() }
        try #require(await waitUntil { clock.pendingCount == 1 })
        clock.advance(by: ceiling)
        await settling.value
        #expect(clock.pendingCount == 0)
    }

    @Test func doesNotWaitForANavigationThatNeverStarts() async throws {
        let webView = makeWebView()
        webView.loadHTMLString(Self.page, baseURL: nil)
        #expect(await PageSettle.untilIdle(webView, timeout: .seconds(30)))

        let clock = TestClock()
        let grace = Duration.seconds(1)
        let settling = Task {
            await PageSettle.afterInteraction(webView, grace: grace, quietCeiling: .zero, clock: clock)
        }
        defer { settling.cancel() }
        try #require(await waitUntil { clock.pendingCount == 1 })
        clock.advance(by: grace)
        await settling.value
        #expect(clock.pendingCount == 0)
        #expect(!webView.isLoading)
    }

    @Test func cancellingALoadWaitReleasesItsObservationAndDeadline() async throws {
        let response = ResponseGate()
        defer { response.open() }
        let server = try await HTTPFixtureServer.start(routes: [
            "/": .html(Self.page, gate: response),
        ])
        let webView = makeWebView()
        defer { webView.stopLoading() }
        webView.load(URLRequest(url: try server.url()))
        try #require(await waitUntil { webView.isLoading && response.requestCount == 1 })

        let clock = TestClock()
        let waiting = Task { await PageSettle.untilIdle(webView, clock: clock) }
        defer { waiting.cancel() }
        try #require(await waitUntil { clock.pendingCount == 1 })
        waiting.cancel()
        #expect(await waiting.value == false)
        #expect(clock.pendingCount == 0)
        #expect(webView.isLoading)
    }

    @Test func survivesRepeatedWaitsOnTheSameView() async {
        let webView = makeWebView()
        for index in 0..<5 {
            webView.loadHTMLString("<html><body>page \(index)</body></html>", baseURL: nil)
            let finished = await PageSettle.untilIdle(webView, timeout: .seconds(30))
            #expect(finished)
        }
        #expect(!webView.isLoading)
    }
}

struct QuiescenceMonitorTests {
    @Test func twoMatchingReadingsAreQuiet() {
        var monitor = QuiescenceMonitor()
        let first = monitor.record(42)
        let second = monitor.record(42)

        #expect(!first)
        #expect(second)
    }

    @Test func aChangeRestartsTheMatchingRun() {
        var monitor = QuiescenceMonitor()
        let first = monitor.record(1)
        let changed = monitor.record(2)
        let repeated = monitor.record(2)

        #expect(!first)
        #expect(!changed)
        #expect(repeated)
    }
}
