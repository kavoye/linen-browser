// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct AgentVisibilityTests {
    private func loadedWebView(_ body: String) async -> WKWebView {
        let configuration = WebViewPool.makeConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 500, height: 400),
            configuration: configuration
        )
        webView.loadHTMLString("<!doctype html><html><body>\(body)</body></html>", baseURL: nil)
        #expect(await PageSettle.untilIdle(webView, timeout: .seconds(30)))
        return webView
    }

    private func ringCount(_ webView: WKWebView) async -> Int {
        (try? await webView.evaluateJavaScript(
            "document.getElementsByClassName('__linen-ring').length"
        )) as? Int ?? -1
    }

    // MARK: - The ring

    @Test func theRingShowsBeforeAnAnnouncedActionLands() async throws {
        let webView = await loadedWebView(#"<button onclick="window.__hit = true">Continue reading</button>"#)
        let observation = await PageDriver.readRenderedPage(webView)
        let ref = try #require(observation.contains("[1]") ? 1 : nil)

        let clock = TestClock()
        try await PageDriver.$pauseSleeper.withValue({ try? await clock.sleep(for: $0) }) {
            let clicking = Task { await PageDriver.click(ref: ref, label: "", in: webView, announced: true) }
            defer { clicking.cancel() }
            try #require(await waitUntil { clock.pendingCount == 1 })
            #expect(await ringCount(webView) > 0)
            #expect((try? await webView.evaluateJavaScript("window.__hit === true")) as? Bool == false)
            clock.advance(by: PageDriver.announcePause)
            let result = await clicking.value
            #expect(result.hasPrefix("Clicked"))
            #expect((try? await webView.evaluateJavaScript("window.__hit === true")) as? Bool == true)
        }
    }

    @Test func theRingCleansUpAfterItself() async throws {
        let webView = await loadedWebView("<button>Fine</button>")
        _ = await PageDriver.click(ref: 0, label: "Fine", in: webView, announced: true)

        #expect(await waitUntil { await ringCount(webView) == 0 })
    }

    @Test func unannouncedActionsDoNotPayTheAnnouncePause() async {
        let webView = await loadedWebView(#"<button onclick="window.__hit = true">Go</button>"#)
        _ = await PageDriver.readRenderedPage(webView)

        // Record requested pauses instead of timing JavaScript round trips,
        // whose duration varies with machine load.
        let requested = PauseRecorder()
        await PageDriver.$pauseSleeper.withValue({ await requested.record($0) }) {
            await PageDriver.announce(ref: 1, in: webView, pause: false)
            #expect(await requested.durations.isEmpty)

            await PageDriver.announce(ref: 1, in: webView, pause: true)
            #expect(await requested.durations == [PageDriver.announcePause])
        }
    }

    private actor PauseRecorder {
        private(set) var durations: [Duration] = []

        func record(_ duration: Duration) {
            durations.append(duration)
        }
    }

    @Test func typingAndSelectingAnnounceTheSameWay() async throws {
        let webView = await loadedWebView("""
        <input placeholder="Search">
        <label for="s">Size</label><select id="s"><option>S</option><option>M</option></select>
        """)
        async let typing = PageDriver.type(
            text: "shoes", intoField: "Search", ref: 0, submit: false, in: webView, announced: true
        )
        let sawRing = await waitUntil { await ringCount(webView) > 0 }
        _ = await typing
        #expect(sawRing)
    }

    // MARK: - Snapshots used by link previews

    @Test func anUnparentedWebViewStillSnapshots() async throws {
        let webView = await loadedWebView(
            #"<div style="background:#3478F6;width:100%;height:100%">Agent page</div>"#
        )
        let image = try #require(await WebViewSnapshot.capture(webView))
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }
}
