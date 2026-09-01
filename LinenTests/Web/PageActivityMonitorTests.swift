// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct PageActivityMonitorTests {
    private func loadedTab() async -> BrowserTab {
        let configuration = WebViewPool.makeConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = TabWebView(
            frame: NSRect(x: 0, y: 0, width: 500, height: 400),
            configuration: configuration
        )
        let permissions = SitePermissions(
            storageURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("PageActivityPermissions-\(UUID().uuidString).json")
        )
        let tab = BrowserTab(
            adopting: webView,
            opensBlank: false,
            sitePermissions: permissions
        )
        tab.loadHTML(
            """
            <!doctype html>
            <form id="profile">
              <input id="name" value="Ada">
              <button>Save</button>
            </form>
            """,
            baseURL: URL(string: "https://example.com/profile")
        )
        #expect(await PageSettle.untilIdle(webView, timeout: .seconds(30)))
        return tab
    }

    @Test func editingAndResettingAFormUpdatesProtection() async throws {
        let tab = await loadedTab()

        try await tab.webView.evaluateJavaScript(
            """
            const field = document.getElementById('name');
            field.dispatchEvent(new FocusEvent('focusin', { bubbles: true }));
            field.value = 'Grace';
            field.dispatchEvent(new Event('input', { bubbles: true }));
            """
        )
        await waitUntil { tab.hasEditedForm }
        #expect(tab.hasEditedForm)
        #expect(!tab.canDiscardWebContent)

        try await tab.webView.evaluateJavaScript("document.getElementById('profile').reset()")
        await waitUntil { !tab.hasEditedForm }
        #expect(!tab.hasEditedForm)
    }

    @Test func returningAFieldToItsOriginalValueClearsProtection() async throws {
        let tab = await loadedTab()

        try await tab.webView.evaluateJavaScript(
            """
            const field = document.getElementById('name');
            field.dispatchEvent(new FocusEvent('focusin', { bubbles: true }));
            field.value = 'Grace';
            field.dispatchEvent(new Event('input', { bubbles: true }));
            """
        )
        await waitUntil { tab.hasEditedForm }

        try await tab.webView.evaluateJavaScript(
            """
            const restoredField = document.getElementById('name');
            restoredField.value = 'Ada';
            restoredField.dispatchEvent(new Event('input', { bubbles: true }));
            """
        )
        await waitUntil { !tab.hasEditedForm }
        #expect(!tab.hasEditedForm)
    }

    private func waitUntil(
        _ condition: () -> Bool,
        limit: Duration = .seconds(2)
    ) async {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline, !condition() {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}
