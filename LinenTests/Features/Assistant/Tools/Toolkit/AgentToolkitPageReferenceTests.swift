// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@MainActor
struct AgentToolkitPageReferenceTests {
    @Test func aContextHeaderLineIsReadAsItsParts() {
        let label = AgentToolkit.contextLabel("1. New Page (127.0.0.1) ← ACTIVE")

        #expect(label.title == "new page")
        #expect(label.host == "127.0.0.1")
        #expect(label.isActive)
        #expect(AgentToolkit.contextLabel("Order summary").title == "order summary")
        #expect(AgentToolkit.contextLabel("Order summary").host == nil)
    }

    @Test func aHeaderLabelMarkedActiveReachesTheActiveTabEvenWithAStaleTitle() throws {
        let browser = BrowserModel(database: .temporary())
        let toolkit = AgentToolkit(browser: browser, media: MediaCenter(), log: ConversationLog(database: .temporary()))
        let tab = browser.newTab(url: try #require(URL(string: "http://127.0.0.1:8123/")))

        #expect(toolkit.pageSurface(named: "New Page (127.0.0.1) ← ACTIVE") === tab.webView)
        #expect(toolkit.pageSurface(named: "Stale title (127.0.0.1)") === tab.webView)
    }
}
