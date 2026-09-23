// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.boundedWebViews)
struct TabRecoveryTests {
    @Test func reloadStartsAnAddressThatHasNotCommitted() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LinenUncommitted-\(UUID().uuidString).html")
        try Data("<title>Loaded</title>".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let tab = BrowserTab(opensBlank: false)
        tab.urlString = url.absoluteString
        #expect(tab.webView.backForwardList.currentItem == nil)

        tab.reload()

        let deadline = ContinuousClock.now + .seconds(3)
        while tab.webView.url != url && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(tab.webView.url == url)
    }

    @Test func restartReplacesOnlyThePageViewAndKeepsItsDataStore() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LinenRecovery-\(UUID().uuidString).html")
        try Data("<title>Recovered</title>".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let configuration = WebViewPool.makeConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let tab = BrowserTab(
            adopting: WebViewPool.shared.makeView(configuration: configuration),
            opensBlank: false,
            privately: true
        )
        let oldView = tab.webView
        tab.urlString = url.absoluteString

        tab.restartPage()

        #expect(tab.webView !== oldView)
        #expect(tab.webView.configuration.websiteDataStore === oldView.configuration.websiteDataStore)
        #expect(oldView.navigationDelegate == nil)
        #expect(oldView.superview == nil)
        #expect(tab.urlString == url.absoluteString)
        #expect(!tab.isClosed)
    }
}
