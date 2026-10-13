// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

@testable import Linen

/// Puts a tab's web view on a real address without a network: the document is
/// local, the origin is the base URL's. The agent's own origin sync reads the
/// web view, so a tab that only claims an address is not a tab it can act on.
@MainActor
func parkTab(_ browser: BrowserModel, at url: URL) async -> BrowserTab {
    let tab = browser.newTab()
    tab.loadHTML("<!doctype html><title>Parked</title><p>Parked</p>", baseURL: url)
    _ = await waitUntil { tab.webView.url == url }
    tab.assistantAccess.persistsAnswers = false
    tab.assistantAccess.pageChanged(url: url)
    return tab
}
