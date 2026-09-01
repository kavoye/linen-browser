// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct AgentAuthoredTextTests {
    private func makeWebView() -> WKWebView {
        WKWebView(frame: .init(x: 0, y: 0, width: 400, height: 300), configuration: WebViewPool.makeConfiguration())
    }

    private func load(_ webView: WKWebView, at url: URL) async {
        webView.loadHTMLString("<!doctype html><html><body>page</body></html>", baseURL: url)
        #expect(await PageSettle.untilIdle(webView, timeout: .seconds(30)))
    }

    @Test func aWebViewNobodyTypedIntoCarriesNoNote() {
        let webView = makeWebView()
        #expect(!AgentAuthoredText.isPresent(in: webView))
    }

    @Test func typingLeavesANoteOnThatPage() async {
        let webView = makeWebView()
        await load(webView, at: URL(string: "https://example.com/compose")!)

        AgentAuthoredText.record(in: webView)
        #expect(AgentAuthoredText.isPresent(in: webView))
    }

    @Test func theNoteBelongsToOneWebViewOnly() async {
        let authored = makeWebView()
        let bystander = makeWebView()
        await load(authored, at: URL(string: "https://example.com/compose")!)
        await load(bystander, at: URL(string: "https://example.com/compose")!)

        AgentAuthoredText.record(in: authored)

        #expect(AgentAuthoredText.isPresent(in: authored))
        #expect(!AgentAuthoredText.isPresent(in: bystander))
    }

    @Test func aNoteSurvivesMovingAroundTheSameSite() async {
        let webView = makeWebView()
        await load(webView, at: URL(string: "https://example.com/compose")!)
        AgentAuthoredText.record(in: webView)

        await load(webView, at: URL(string: "https://example.com/compose/step-two")!)

        #expect(AgentAuthoredText.isPresent(in: webView))
    }

    @Test func landingOnAnotherSiteDropsTheNote() async {
        let webView = makeWebView()
        await load(webView, at: URL(string: "https://example.com/compose")!)
        AgentAuthoredText.record(in: webView)

        await load(webView, at: URL(string: "https://elsewhere.example/post")!)

        #expect(!AgentAuthoredText.isPresent(in: webView))
    }

    @Test func aSubdomainCountsAsAnotherSite() async {
        let webView = makeWebView()
        await load(webView, at: URL(string: "https://example.com/compose")!)
        AgentAuthoredText.record(in: webView)

        await load(webView, at: URL(string: "https://mail.example.com/compose")!)

        #expect(!AgentAuthoredText.isPresent(in: webView))
    }

    @Test func postingClearsTheNoteSoTheNextPostAsksAgain() async {
        let webView = makeWebView()
        await load(webView, at: URL(string: "https://example.com/compose")!)
        AgentAuthoredText.record(in: webView)

        AgentAuthoredText.clear(in: webView)

        #expect(!AgentAuthoredText.isPresent(in: webView))
    }

    @Test func clearingAWebViewNobodyRecordedIsHarmless() {
        let webView = makeWebView()
        AgentAuthoredText.clear(in: webView)
        #expect(!AgentAuthoredText.isPresent(in: webView))
    }

    @Test func recordingAgainAfterAPostRestoresTheNote() async {
        let webView = makeWebView()
        await load(webView, at: URL(string: "https://example.com/compose")!)
        AgentAuthoredText.record(in: webView)
        AgentAuthoredText.clear(in: webView)

        AgentAuthoredText.record(in: webView)

        #expect(AgentAuthoredText.isPresent(in: webView))
    }
}
