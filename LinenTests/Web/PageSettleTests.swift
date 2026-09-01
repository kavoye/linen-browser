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
        let started = await loadStarted(webView)

        let finished = await PageSettle.untilIdle(webView, timeout: .seconds(30))

        #expect(started)
        #expect(finished)
        #expect(!webView.isLoading)
        let text = (try? await webView.evaluateJavaScript("document.body.textContent")) as? String
        #expect(text?.contains("Hello") == true)
    }

    private func loadStarted(_ webView: WKWebView, within: Duration = .seconds(5)) async -> Bool {
        let deadline = ContinuousClock.now + within
        while ContinuousClock.now < deadline {
            if webView.isLoading {
                return true
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    @Test func returnsAtOnceWhenThereIsNoLoadInFlight() async {
        let webView = makeWebView()
        webView.loadHTMLString(Self.page, baseURL: nil)
        #expect(await PageSettle.untilIdle(webView, timeout: .seconds(30)))

        let clock = ContinuousClock()
        let elapsed = await clock.measure {
            _ = await PageSettle.untilIdle(webView, timeout: .seconds(30))
        }
        #expect(elapsed < .milliseconds(50))
    }

    @Test func aStaticDOMReturnsWellBeforeTheCeiling() async {
        let webView = makeWebView()
        webView.loadHTMLString(Self.page, baseURL: nil)
        #expect(await PageSettle.untilIdle(webView, timeout: .seconds(30)))

        let clock = ContinuousClock()
        let elapsed = await clock.measure {
            await PageSettle.untilQuiet(webView, ceiling: .seconds(5))
        }
        #expect(elapsed < .seconds(4), "a static page should not run to the five-second ceiling")
    }

    @Test func neverWaitsLongerThanItsCeiling() async {
        let webView = makeWebView()
        webView.loadHTMLString("""
        <!doctype html><html><body><div id="churn"></div><script>
          setInterval(() => {
            document.getElementById('churn').appendChild(document.createElement('span'));
          }, 20);
        </script></body></html>
        """, baseURL: nil)
        #expect(await PageSettle.untilIdle(webView, timeout: .seconds(30)))

        let ceiling = Duration.milliseconds(600)
        let clock = ContinuousClock()
        let elapsed = await clock.measure {
            await PageSettle.untilQuiet(webView, ceiling: ceiling)
        }
        // One sampling interval of slack: the deadline is checked at the top
        // of the loop, so the last sleep can carry it just past.
        #expect(elapsed < ceiling + .milliseconds(400))
    }

    @Test func doesNotWaitForANavigationThatNeverStarts() async {
        let webView = makeWebView()
        webView.loadHTMLString(Self.page, baseURL: nil)
        #expect(await PageSettle.untilIdle(webView, timeout: .seconds(30)))

        let clock = ContinuousClock()
        let elapsed = await clock.measure {
            await PageSettle.afterInteraction(
                webView,
                grace: .milliseconds(200),
                quietCeiling: .milliseconds(600)
            )
        }
        #expect(elapsed >= .milliseconds(180))
        #expect(elapsed < .seconds(3))
        #expect(!webView.isLoading)
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
