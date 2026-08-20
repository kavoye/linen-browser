// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation

@MainActor
enum ExternalApp {
    private nonisolated static let webSchemes: Set<String> = [
        "http", "https", "about", "blob", "data", "file", "javascript", "webkit-extension",
    ]

    nonisolated static func staysInWebView(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return true }
        return webSchemes.contains(scheme)
    }

    static func offerToOpen(_ url: URL, in window: NSWindow?) async {
        guard let window else { return }
        let alert = NSAlert()

        guard let app = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            alert.messageText = String(localized: "No app can open this link.")
            alert.informativeText = String(
                localized: "Nothing installed on this Mac handles “\(url.scheme ?? "")” links."
            )
            alert.addButton(withTitle: String(localized: "OK"))
            _ = await present(alert, in: window)
            return
        }

        let name = FileManager.default.displayName(atPath: app.path)
        alert.messageText = String(localized: "Do you want to allow this page to open “\(name)”?")
        alert.addButton(withTitle: String(localized: "Allow"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard await present(alert, in: window) == .alertFirstButtonReturn else { return }
        NSWorkspace.shared.open(url)
    }

    private static func present(_ alert: NSAlert, in window: NSWindow) async -> NSApplication.ModalResponse {
        await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response)
            }
        }
    }
}
