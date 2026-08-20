// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct NotificationShimTests {
    private func page() async -> WKWebView {
        let webView = WKWebView(
            frame: .init(x: 0, y: 0, width: 400, height: 300),
            configuration: WKWebViewConfiguration()
        )
        webView.loadHTMLString("<!doctype html><html><body>page</body></html>", baseURL: nil)
        #expect(await PageSettle.untilIdle(webView, timeout: .seconds(30)))
        return webView
    }

    private func installStubHandler(in webView: WKWebView) async {
        _ = try? await webView.evaluateJavaScript("""
            window.__posted = [];
            window.webkit = {
              messageHandlers: {
                linennotify: { postMessage: function (m) { window.__posted.push(m); } }
              }
            };
            true;
            """)
    }

    private func run(_ script: String, in webView: WKWebView) async -> Any? {
        try? await webView.evaluateJavaScript(script)
    }

    private func posted(in webView: WKWebView) async -> [[String: Any]] {
        let json = await run("JSON.stringify(window.__posted)", in: webView) as? String ?? "[]"
        let parsed = try? JSONSerialization.jsonObject(with: Data(json.utf8))
        return parsed as? [[String: Any]] ?? []
    }

    private func armed() async -> WKWebView {
        let webView = await page()
        await installStubHandler(in: webView)
        _ = await run(NotificationBridge.scriptSource, in: webView)
        return webView
    }

    // MARK: - Installing

    @Test func aPageWithNoHandlerKeepsWhateverNotificationItHad() async {
        let webView = await page()
        _ = await run("window.Notification = 'untouched'; true;", in: webView)

        _ = await run(NotificationBridge.scriptSource, in: webView)

        #expect(await run("window.Notification", in: webView) as? String == "untouched")
    }

    @Test func theShimAnnouncesItselfAsSoonAsItIsInstalled() async {
        let webView = await armed()

        let messages = await posted(in: webView)

        #expect(messages.first?["type"] as? String == "hello")
    }

    @Test func thePageGetsANotificationConstructor() async {
        let webView = await armed()
        #expect(await run("typeof window.Notification", in: webView) as? String == "function")
    }

    // MARK: - Permission

    @Test func permissionStartsUndecided() async {
        let webView = await armed()
        #expect(await run("Notification.permission", in: webView) as? String == "default")
    }

    @Test func theBrowserCanSetThePermissionWithoutBeingAsked() async {
        let webView = await armed()

        _ = await run("window.__linenNotify.setPermission('granted')", in: webView)

        #expect(await run("Notification.permission", in: webView) as? String == "granted")
    }

    @Test func askingForPermissionPostsARequestCarryingItsOwnID() async {
        let webView = await armed()

        _ = await run("window.__pending = Notification.requestPermission()", in: webView)

        let request = await posted(in: webView).first { $0["type"] as? String == "request" }
        #expect(request != nil)
        #expect(request?["id"] as? Int == 1)
    }

    @Test func twoRequestsAreToldApartByTheirIDs() async {
        let webView = await armed()

        _ = await run("Notification.requestPermission(); Notification.requestPermission();", in: webView)

        let ids = await posted(in: webView)
            .filter { $0["type"] as? String == "request" }
            .compactMap { $0["id"] as? Int }
        #expect(ids == [1, 2])
    }

    @Test func answeringARequestSettlesItsPromise() async {
        let webView = await armed()
        _ = await run("""
            window.__answer = null;
            Notification.requestPermission().then(function (v) { window.__answer = v; });
            true;
            """, in: webView)

        _ = await run("window.__linenNotify.resolve(1, 'granted')", in: webView)
        _ = await run("new Promise(function (r) { setTimeout(r, 0); })", in: webView)

        #expect(await run("window.__answer", in: webView) as? String == "granted")
        #expect(await run("Notification.permission", in: webView) as? String == "granted")
    }

    @Test func aRefusalIsRememberedAsARefusal() async {
        let webView = await armed()
        _ = await run("Notification.requestPermission()", in: webView)

        _ = await run("window.__linenNotify.resolve(1, 'denied')", in: webView)

        #expect(await run("Notification.permission", in: webView) as? String == "denied")
    }

    @Test func anUndecidedAnswerLeavesAnEarlierDecisionStanding() async {
        let webView = await armed()
        _ = await run("window.__linenNotify.setPermission('granted')", in: webView)
        _ = await run("Notification.requestPermission()", in: webView)

        _ = await run("window.__linenNotify.resolve(1, 'default')", in: webView)

        #expect(await run("Notification.permission", in: webView) as? String == "granted")
    }

    @Test func theOldCallbackFormIsAnsweredToo() async {
        let webView = await armed()
        _ = await run("""
            window.__called = null;
            Notification.requestPermission(function (v) { window.__called = v; });
            true;
            """, in: webView)

        _ = await run("window.__linenNotify.resolve(1, 'granted')", in: webView)

        #expect(await run("window.__called", in: webView) as? String == "granted")
    }

    @Test func aCallbackThatThrowsStillLetsThePromiseSettle() async {
        let webView = await armed()
        _ = await run("""
            window.__answer = null;
            Notification.requestPermission(function () { throw new Error('page bug'); })
              .then(function (v) { window.__answer = v; });
            true;
            """, in: webView)

        _ = await run("window.__linenNotify.resolve(1, 'granted')", in: webView)
        _ = await run("new Promise(function (r) { setTimeout(r, 0); })", in: webView)

        #expect(await run("window.__answer", in: webView) as? String == "granted")
    }

    @Test func aRequestsCallbackRunsOnlyOnce() async {
        let webView = await armed()
        _ = await run("""
            window.__calls = 0;
            Notification.requestPermission(function () { window.__calls += 1; });
            true;
            """, in: webView)

        _ = await run("window.__linenNotify.resolve(1, 'granted')", in: webView)
        _ = await run("window.__linenNotify.resolve(1, 'granted')", in: webView)

        #expect(await run("window.__calls", in: webView) as? Int == 1)
    }

    @Test func anAnswerForAnotherRequestSettlesNothing() async {
        let webView = await armed()
        _ = await run("""
            window.__answer = 'unsettled';
            Notification.requestPermission().then(function (v) { window.__answer = v; });
            true;
            """, in: webView)

        _ = await run("window.__linenNotify.resolve(99, 'granted')", in: webView)
        _ = await run("new Promise(function (r) { setTimeout(r, 0); })", in: webView)

        #expect(await run("window.__answer", in: webView) as? String == "unsettled")
    }

    // MARK: - Showing one

    @Test func showingANotificationPostsItsText() async {
        let webView = await armed()

        _ = await run("new Notification('Title here', { body: 'Body here', tag: 'chat' })", in: webView)

        let shown = await posted(in: webView).first { $0["type"] as? String == "show" }
        #expect(shown?["title"] as? String == "Title here")
        #expect(shown?["body"] as? String == "Body here")
        #expect(shown?["tag"] as? String == "chat")
    }

    @Test func aNotificationWithNoOptionsStillPosts() async {
        let webView = await armed()

        _ = await run("new Notification('Bare')", in: webView)

        let shown = await posted(in: webView).first { $0["type"] as? String == "show" }
        #expect(shown?["title"] as? String == "Bare")
        #expect(shown?["body"] as? String == "")
        #expect(shown?["tag"] as? String == "")
    }

    @Test func anythingPassedAsATitleIsSentAsText() async {
        let webView = await armed()

        _ = await run("new Notification(42)", in: webView)

        #expect(await posted(in: webView).first { $0["type"] as? String == "show" }?["title"] as? String == "42")
    }

    @Test func closingANotificationIsHarmless() async {
        let webView = await armed()

        let result = await run("var n = new Notification('x'); n.close(); 'survived';", in: webView)

        #expect(result as? String == "survived")
    }

    @Test func theShimAdvertisesNoActionButtons() async {
        let webView = await armed()
        #expect(await run("Notification.maxActions", in: webView) as? Int == 0)
    }
}
