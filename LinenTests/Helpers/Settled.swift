// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

/// Waits for a tab to be standing on an address rather than on its way to one.
/// A commit is not the end of a navigation, and asking for the next page while
/// WebKit is still finishing the last one is a race no person can run.
///
/// A timeout says which half of that ran out: the address it stopped at, and
/// whether WebKit was still loading. Without it the failure reads as a bare
/// false and every diagnosis starts from nothing.
@MainActor
func settled(
    _ tab: BrowserTab,
    at url: URL?,
    sourceLocation: SourceLocation = #_sourceLocation
) async -> Bool {
    let reached = await waitUntil {
        guard !tab.webView.isLoading else { return false }
        guard tab.committedURL != url else { return true }
        // A back served from the page cache fires no navigation callback and
        // leaves WebKit's list naming the page that has gone. The view's own
        // URL does not lag, and with nothing loading it is what the tab is
        // standing on — the same rule `internalPage` reads by.
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
