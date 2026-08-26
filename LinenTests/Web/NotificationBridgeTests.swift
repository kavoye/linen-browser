// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

/// The Notification API a page sees is Linen's, not WebKit's. What the page
/// is told about its permission has to match what the browser actually
/// stored, because that string is the whole gate: a page that believes it is
/// granted will go on to post.
@MainActor
@Suite(.serialized, .boundedWebViews)
struct NotificationBridgeTests {
    private let origin = "https://notify.example"

    /// The same shim the pool installs, in a view of this test's own: the
    /// pool is only loaded with scripts once the app has bootstrapped.
    private func page(policy: PermissionPolicy) async -> (BrowserTab, WKWebView) {
        let permissions = SitePermissions(
            storageURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("linen-notify-\(UUID().uuidString).json")
        )
        let tab = BrowserTab(opensBlank: false, sitePermissions: permissions)
        permissions.set(policy, for: origin, .notifications)
        tab.permissions.pageChanged(url: URL(string: origin))
        NotificationBridge.shared.tabResolver = { _ in tab }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(
            source: NotificationBridge.scriptSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        controller.add(NotificationBridge.shared, name: NotificationBridge.handlerName)
        configuration.userContentController = controller

        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 300, height: 200),
            configuration: configuration
        )
        webView.loadHTMLString(
            "<!doctype html><title>Notify</title><body>hi</body>",
            baseURL: URL(string: origin)
        )
        _ = await PageSettle.untilIdle(webView, timeout: .seconds(10))
        return (tab, webView)
    }

    private func permissionSeenByThePage(_ webView: WKWebView) async -> String? {
        var seen: String?
        _ = await waitUntil {
            seen = (try? await webView.evaluateJavaScript("Notification.permission")) as? String
            return seen != nil && seen != "default"
        }
        return seen
    }

    @Test func thePageIsGivenLinensOwnNotificationApi() async {
        let (tab, webView) = await page(policy: .ask)
        defer { NotificationBridge.shared.tabResolver = nil; tab.detach() }

        let kind = (try? await webView.evaluateJavaScript("typeof Notification")) as? String
        let requester = (try? await webView.evaluateJavaScript(
            "typeof Notification.requestPermission"
        )) as? String

        #expect(kind == "function")
        #expect(requester == "function")
    }

    @Test func aWebsiteYouHaveAllowedIsToldItIsGranted() async {
        let (tab, webView) = await page(policy: .allow)
        defer { NotificationBridge.shared.tabResolver = nil; tab.detach() }

        #expect(await permissionSeenByThePage(webView) == "granted")
    }

    @Test func aWebsiteYouHaveRefusedIsToldSo() async {
        let (tab, webView) = await page(policy: .deny)
        defer { NotificationBridge.shared.tabResolver = nil; tab.detach() }

        #expect(await permissionSeenByThePage(webView) == "denied")
    }

    /// Until the person answers, the page is told nothing either way — the
    /// default that makes a well-behaved site ask rather than post.
    @Test func aWebsiteYouHaveNotAnsweredForIsToldNothingYet() async {
        let (tab, webView) = await page(policy: .ask)
        defer { NotificationBridge.shared.tabResolver = nil; tab.detach() }

        let seen = (try? await webView.evaluateJavaScript("Notification.permission")) as? String
        #expect(seen == "default")
    }

    /// A refused website asking again is answered from what was stored, with
    /// no prompt: the refusal is the answer.
    @Test func askingAgainAfterARefusalIsAnsweredWithoutAskingYou() async {
        let (tab, webView) = await page(policy: .deny)
        defer { NotificationBridge.shared.tabResolver = nil; tab.detach() }

        _ = try? await webView.evaluateJavaScript(
            "Notification.requestPermission().then(function (v) { window.__answer = v })"
        )

        var answer: String?
        let settled = await waitUntil {
            answer = (try? await webView.evaluateJavaScript("window.__answer")) as? String
            return answer != nil
        }

        #expect(settled)
        #expect(answer == "denied")
        #expect(tab.permissions.live.isEmpty, "a refusal never turns anything on")
    }

    @Test func theShimIsWhatTheBrowserPutThereNotThePages() async {
        let (tab, webView) = await page(policy: .allow)
        defer { NotificationBridge.shared.tabResolver = nil; tab.detach() }

        let hasHook = (try? await webView.evaluateJavaScript(
            "typeof window.__linenNotify.setPermission"
        )) as? String

        #expect(hasHook == "function", "the browser keeps a way to answer the page")
    }
}
