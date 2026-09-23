// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import WebKit

@MainActor
enum WebViewSnapshot {
    static func capture(_ webView: WKWebView, width: CGFloat = 480) async -> NSImage? {
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = NSNumber(value: Double(width))
        return try? await webView.takeSnapshot(configuration: configuration)
    }
}
