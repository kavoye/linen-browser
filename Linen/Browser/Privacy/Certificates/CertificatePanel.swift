// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Security
import SecurityInterface
import WebKit

@MainActor
enum CertificatePanel {
    static func trust(of tab: BrowserTab) -> SecTrust? {
        guard tab.isMaterialised, tab.security != .none, tab.security != .insecure else { return nil }
        return tab.webView.serverTrust
    }

    static func canShow(for tab: BrowserTab) -> Bool {
        trust(of: tab) != nil
    }

    static func show(for tab: BrowserTab, in window: NSWindow? = nil) {
        guard let trust = trust(of: tab) else { return }
        show(trust, host: URL(string: tab.urlString)?.host(), in: window)
    }

    static func show(_ trust: SecTrust, host: String?, in window: NSWindow? = nil) {
        guard let window = window ?? NSApp.keyWindow ?? NSApp.mainWindow,
              let panel = SFCertificatePanel.shared()
        else { return }
        if let host {
            panel.setPolicies(SecPolicyCreateSSL(true, host as CFString))
        }
        panel.beginSheet(
            for: window,
            modalDelegate: nil,
            didEnd: nil,
            contextInfo: nil,
            trust: trust,
            showGroup: true
        )
    }
}
