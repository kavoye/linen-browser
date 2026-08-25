// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

@testable import Linen

/// Waits for a tab to be standing on an address rather than on its way to one.
/// A commit is not the end of a navigation, and asking for the next page while
/// WebKit is still finishing the last one is a race no person can run.
@MainActor
func settled(_ tab: BrowserTab, at url: URL?) async -> Bool {
    await waitUntil { tab.committedURL == url && !tab.webView.isLoading }
}
