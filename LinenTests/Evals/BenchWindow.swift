// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import WebKit

@testable import Linen

@MainActor
final class BenchWindow {
    private let window: NSWindow?

    init(headless: Bool) {
        guard !headless else { window = nil; return }
        let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 1100, height: 800),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Linen workflow benchmark"
        window.isReleasedWhenClosed = false
        self.window = window
    }

    func update(_ browser: BrowserModel) {
        guard let window, let view = browser.activeTab?.webView, window.contentView !== view else { return }
        window.contentView = view
        window.orderBack(nil)
    }

    func close() {
        window?.contentView = nil
        window?.close()
    }
}
