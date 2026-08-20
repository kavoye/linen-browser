// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

/// The visible half of agency: the ring that shows what is about to be
/// pressed, and the thumbnail that shows the hidden page. Both against real
/// web views, because both are rendering behavior.
@MainActor
@Suite(.serialized, .boundedWebViews)
struct AgentVisibilityTests {
    private func loadedWebView(_ body: String) async -> WKWebView {
        let configuration = WKWebViewConfiguration()
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

    /// An announced click draws the ring *before* the action lands: while
    /// the click is still holding its pause, the ring is already on screen
    /// and the button has not yet been pressed.
    @Test func theRingShowsBeforeAnAnnouncedActionLands() async throws {
        let webView = await loadedWebView(#"<button onclick="window.__hit = true">Continue reading</button>"#)
        let observation = await PageDriver.readRenderedPage(webView)
        let ref = try #require(observation.contains("[1]") ? 1 : nil)

        async let clicking = PageDriver.click(ref: ref, label: "", in: webView, announced: true)

        // Sample during the announce pause: ring present, effect absent.
        var sawRingBeforeEffect = false
        let sampleDeadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < sampleDeadline {
            let rings = await ringCount(webView)
            let hit = (try? await webView.evaluateJavaScript("window.__hit === true")) as? Bool ?? false
            if rings > 0, !hit {
                sawRingBeforeEffect = true
                break
            }
            if hit {
                break
            }
            try? await Task.sleep(for: .milliseconds(20))
        }

        let result = await clicking
        #expect(result.hasPrefix("Clicked"))
        #expect(sawRingBeforeEffect, "the ring should be visible before the click takes effect")
        #expect((try? await webView.evaluateJavaScript("window.__hit === true")) as? Bool == true)
    }

    /// Nothing the ring draws survives its moment: it fades and removes
    /// itself, leaving the page exactly as it was.
    @Test func theRingCleansUpAfterItself() async throws {
        let webView = await loadedWebView("<button>Fine</button>")
        _ = await PageDriver.click(ref: 0, label: "Fine", in: webView, announced: true)

        #expect(await waitUntil { await ringCount(webView) == 0 })
    }

    /// Unannounced actions - the hidden research surface - draw the ring too
    /// (the thumbnail picks it up) but never pause for an audience that
    /// isn't there.
    @Test func unannouncedActionsDoNotPayTheAnnouncePause() async {
        let webView = await loadedWebView(#"<button onclick="window.__hit = true">Go</button>"#)
        _ = await PageDriver.readRenderedPage(webView)

        // Asked, not timed: timing compared one JS round trip against the
        // pause's duration, which is a question about machine load - it failed
        // by 18ms once in a parallel run. The recorder answers the real
        // question: which path asks for a pause, and for how long.
        let requested = PauseRecorder()
        await PageDriver.$pauseSleeper.withValue({ await requested.record($0) }) {
            await PageDriver.announce(ref: 1, in: webView, pause: false)
            #expect(await requested.durations.isEmpty)

            await PageDriver.announce(ref: 1, in: webView, pause: true)
            #expect(await requested.durations == [PageDriver.announcePause])
        }
    }

    /// Collects the pauses `PageDriver` asks for instead of serving them, so
    /// the announced path costs a test nothing to assert on.
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

    // MARK: - The thumbnail

    /// The load-bearing assumption: a web view that is in no window renders
    /// into a snapshot anyway. If this stops being true, the card goes
    /// permanently blank and nothing else would say why.
    @Test func anUnparentedWebViewStillSnapshots() async throws {
        let webView = await loadedWebView(
            #"<div style="background:#3478F6;width:100%;height:100%">Agent page</div>"#
        )
        let image = try #require(await ResearchPreview.capture(webView))
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }

    @Test func thePreviewLoopPublishesFramesAndTheHost() async {
        let webView = await loadedWebView("<h1>Research in progress</h1>")
        let preview = ResearchPreview()
        preview.source = { webView }

        preview.begin()
        #expect(preview.isLive)
        #expect(preview.snapshot == nil, "begin clears the previous task's frame")

        var frames = 0
        for _ in 0..<40 {
            if preview.snapshot != nil {
                frames += 1
                break
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        #expect(frames > 0, "a frame should arrive within the loop's first ticks")

        preview.end()
        #expect(!preview.isLive)
        #expect(preview.snapshot != nil, "the last frame outlives the task, dimmed rather than blanked")
    }

    /// No research surface, no frames - and no crash asking for them.
    @Test func thePreviewLoopIdlesWhenThereIsNothingToShow() async {
        let preview = ResearchPreview()
        preview.source = { nil }
        preview.begin()
        try? await Task.sleep(for: .milliseconds(400))
        #expect(preview.snapshot == nil)
        preview.end()
    }
}
