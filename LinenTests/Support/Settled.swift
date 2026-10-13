// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

/// Wait for the expected URL and for WebKit to finish loading before starting another navigation.
/// Report the current URL and loading state on timeout.
@MainActor
func settled(
    _ tab: BrowserTab,
    at url: URL?,
    sourceLocation: SourceLocation = #_sourceLocation
) async -> Bool {
    let reached = await waitUntil {
        guard !tab.webView.isLoading else { return false }
        guard tab.committedURL != url else { return true }
        // Page-cache restores may skip navigation callbacks and leave `committedURL` stale.
        // Use the idle web view's URL as a fallback, as `internalPage` does.
        return tab.isMaterialised && tab.webView.url == url
    }
    guard !reached else { return true }
    Issue.record(
        """
        settle timed out: standing at \(tab.committedURL?.absoluteString ?? "nothing"), \
        view at \(tab.isMaterialised ? (tab.webView.url?.absoluteString ?? "nothing") : "no view"), \
        wanted \(url?.absoluteString ?? "nothing"), \
        WebKit loading \(tab.webView.isLoading), tab loading \(tab.isLoading)
        """,
        sourceLocation: sourceLocation
    )
    return false
}
