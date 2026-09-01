// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Testing
import WebKit

@testable import Linen

/// The gate a pull must pass before the page starts moving: the document at
/// its top, and the pointer over the page itself - not over a chat, feed or
/// any other list scrolling inside it, where the wheel belongs to that list.
@MainActor
struct PullToRefreshGateTests {
    private func ancestor(
        overflowY: String,
        scrollHeight: Double = 2000,
        clientHeight: Double = 400
    ) -> PullStartProbe.Ancestor {
        PullStartProbe.Ancestor(
            overflowY: overflowY,
            scrollHeight: scrollHeight,
            clientHeight: clientHeight
        )
    }

    @Test func aPlainPageAtItsTopMayPull() {
        #expect(PullToRefreshMonitor.canBeginPull(PullStartProbe(scrollY: 0, ancestors: [])))
    }

    @Test func aScrolledPageMayNot() {
        #expect(!PullToRefreshMonitor.canBeginPull(PullStartProbe(scrollY: 480, ancestors: [])))
    }

    /// WebKit reports a fractional offset at rest because of the rubber band;
    /// that is still the top.
    @Test func theRubberBandFractionStillCountsAsTop() {
        #expect(PullToRefreshMonitor.canBeginPull(PullStartProbe(scrollY: 0.5, ancestors: [])))
    }

    /// The bug: a chat column at the page's top consumed the wheel, the
    /// document never moved, and the scrollY-only check read the gesture as
    /// a pull.
    @Test(arguments: ["auto", "scroll", "overlay"])
    func aPointerOverAnInnerScrollerMayNotPull(overflowY: String) {
        let probe = PullStartProbe(scrollY: 0, ancestors: [ancestor(overflowY: overflowY)])
        #expect(!PullToRefreshMonitor.canBeginPull(probe))
    }

    @Test func theInnerScrollerDisqualifiesFromAnywhereInTheChain() {
        let probe = PullStartProbe(scrollY: 0, ancestors: [
            ancestor(overflowY: "visible", scrollHeight: 400, clientHeight: 400),
            ancestor(overflowY: "auto"),
            ancestor(overflowY: "visible", scrollHeight: 3000, clientHeight: 3000),
        ])
        #expect(!PullToRefreshMonitor.canBeginPull(probe))
    }

    /// A scroll container with nothing to scroll gives the wheel nothing and
    /// the document moves - that is a pull.
    @Test func anInnerContainerWithNoOverflowDoesNotDisqualify() {
        let probe = PullStartProbe(scrollY: 0, ancestors: [
            ancestor(overflowY: "auto", scrollHeight: 400, clientHeight: 400),
        ])
        #expect(PullToRefreshMonitor.canBeginPull(probe))
    }

    /// `overflow: hidden` keeps its overflow but the wheel cannot reach it.
    @Test func hiddenOverflowDoesNotDisqualify() {
        let probe = PullStartProbe(scrollY: 0, ancestors: [ancestor(overflowY: "hidden")])
        #expect(PullToRefreshMonitor.canBeginPull(probe))
    }

    /// Tall content inside an ordinary element scrolls with the document.
    @Test func aTallElementWithVisibleOverflowDoesNotDisqualify() {
        let probe = PullStartProbe(scrollY: 0, ancestors: [ancestor(overflowY: "visible")])
        #expect(PullToRefreshMonitor.canBeginPull(probe))
    }

    @Test func decodeReadsThePagesAnswerAndRefusesGarbage() {
        let decoded = PullStartProbe.decode(
            #"{"scrollY":12,"ancestors":[{"overflowY":"auto","scrollHeight":900,"clientHeight":300}]}"#
        )
        #expect(decoded == PullStartProbe(
            scrollY: 12,
            ancestors: [ancestor(overflowY: "auto", scrollHeight: 900, clientHeight: 300)]
        ))
        #expect(PullStartProbe.decode("not json") == nil)
    }
}

/// The second gate: which view the wheel landed on. A sidebar peeking over the
/// page, and a side panel standing on top of it, both sit inside the page's
/// rectangle, so the pointer being within those bounds proves nothing.
@MainActor
struct PullToRefreshOwnershipTests {
    private func page() -> NSView {
        NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    }

    @Test func theWheelOnThePageItselfIsAPull() {
        let page = page()
        #expect(PullToRefreshMonitor.pageOwnsScroll(hit: page, page: page))
    }

    /// WebKit hit-tests to its own inner content view, never the WKWebView.
    @Test func theWheelOnAViewInsideThePageIsAPull() {
        let page = page()
        let content = NSView(frame: page.bounds)
        page.addSubview(content)
        #expect(PullToRefreshMonitor.pageOwnsScroll(hit: content, page: page))
    }

    /// The bug: chrome standing over the page kept the page's bounds check
    /// true, so scrolling the sidebar or the side panel pulled the tab.
    @Test func theWheelOnChromeOverThePageIsNot() {
        let page = page()
        let chrome = NSView(frame: NSRect(x: 0, y: 0, width: 268, height: 600))
        #expect(!PullToRefreshMonitor.pageOwnsScroll(hit: chrome, page: page))
    }

    @Test func aWheelThatLandsOnNothingIsNot() {
        #expect(!PullToRefreshMonitor.pageOwnsScroll(hit: nil, page: page()))
    }

    /// A split's other pane is a sibling, not an ancestor: only the active
    /// tab's view may pull.
    @Test func theWheelOnTheOtherSplitPaneIsNot() {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let active = page()
        let other = page()
        host.addSubview(active)
        host.addSubview(other)
        #expect(!PullToRefreshMonitor.pageOwnsScroll(hit: other, page: active))
    }
}

/// The probe's JavaScript against a real page, so the DOM walk the decision
/// rests on is pinned too.
@MainActor
@Suite(.serialized, .boundedWebViews)
struct PullToRefreshProbeTests {
    private func loadedWebView(_ body: String) async -> WKWebView {
        let configuration = WebViewPool.makeConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 500, height: 400),
            configuration: configuration
        )
        webView.loadHTMLString(
            "<!doctype html><html><body style=\"margin:0\">\(body)</body></html>",
            baseURL: nil
        )
        #expect(await PageSettle.untilIdle(webView, timeout: .seconds(30)))
        return webView
    }

    private func probe(_ webView: WKWebView, x: CGFloat, y: CGFloat) async throws -> PullStartProbe {
        let answer = try #require(
            (try? await webView.evaluateJavaScript(
                PullToRefreshMonitor.startProbeScript(x: x, y: y)
            )) as? String
        )
        return try #require(PullStartProbe.decode(answer))
    }

    @Test func theProbeSeesTheInnerScrollerAndOnlyIt() async throws {
        let webView = await loadedWebView("""
        <div style="height: 3000px">
            <div id="chat" style="position: absolute; top: 50px; left: 0; width: 300px; height: 200px; overflow-y: auto">
                <div style="height: 2000px">messages</div>
            </div>
        </div>
        """)

        let overChat = try await probe(webView, x: 150, y: 150)
        #expect(overChat.ancestors.contains { $0.consumesVerticalScroll })
        #expect(!PullToRefreshMonitor.canBeginPull(overChat))

        let overPage = try await probe(webView, x: 450, y: 30)
        #expect(!overPage.ancestors.contains { $0.consumesVerticalScroll })
        #expect(PullToRefreshMonitor.canBeginPull(overPage))
    }

    @Test func theProbeReportsTheDocumentsOwnScroll() async throws {
        let webView = await loadedWebView("<div style=\"height: 3000px\">tall</div>")
        _ = try? await webView.evaluateJavaScript("window.scrollTo(0, 700)")

        let scrolled = try await probe(webView, x: 250, y: 200)
        #expect(scrolled.scrollY == 700)
        #expect(!PullToRefreshMonitor.canBeginPull(scrolled))
    }
}
