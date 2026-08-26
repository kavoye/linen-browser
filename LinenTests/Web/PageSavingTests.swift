// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

/// What a saved page is called. The name comes from the page itself, so it
/// carries whatever the page put in its title — including the characters a
/// file system refuses.
@MainActor
@Suite(.boundedWebViews)
struct PageSavingTests {
    private func page(title: String?, at address: String?) async -> WKWebView {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let head = title.map { "<title>\($0)</title>" } ?? ""
        if let address, let url = URL(string: address) {
            webView.loadHTMLString("<!doctype html>\(head)<body>hi</body>", baseURL: url)
        } else {
            webView.loadHTMLString("<!doctype html>\(head)<body>hi</body>", baseURL: nil)
        }
        _ = await PageSettle.untilIdle(webView, timeout: .seconds(10))
        if title != nil {
            _ = await waitUntil { !(webView.title ?? "").isEmpty }
        }
        return webView
    }

    @Test func aPageIsNamedAfterItsTitle() async {
        let webView = await page(title: "Quarterly Report", at: "https://example.com/q3")

        #expect(PageSaving.filename(for: webView) == "Quarterly Report.webarchive")
    }

    @Test func aPageWithNoTitleIsNamedAfterItsHost() async {
        let webView = await page(title: nil, at: "https://www.example.com/q3")

        #expect(PageSaving.filename(for: webView) == "example.com.webarchive")
    }

    @Test func aTitleThatWouldBreakTheFileSystemIsMadeSafe() async {
        let webView = await page(title: "Report: 2026/2027 · draft", at: "https://example.com/")
        let name = PageSaving.filename(for: webView)

        #expect(!name.contains("/"))
        #expect(name.hasSuffix(".webarchive"))
    }

    @Test func aPageWithNothingToGoOnStillGetsAName() async {
        let webView = await page(title: nil, at: nil)
        let name = PageSaving.filename(for: webView)

        #expect(name.hasSuffix(".webarchive"))
        #expect(name.count > ".webarchive".count, "a nameless page still needs a filename")
    }
}
