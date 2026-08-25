// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation

nonisolated struct ExternalAppMatch: Sendable {
    let url: URL
    let name: String
}

@MainActor
enum ExternalApp {
    typealias Match = ExternalAppMatch

    private nonisolated static let webSchemes: Set<String> = [
        "http", "https", "about", "blob", "data", "file", "javascript", "webkit-extension",
    ]

    nonisolated static func staysInWebView(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return true }
        return webSchemes.contains(scheme)
    }

    static var openerForTesting: ((URL) -> Void)?

    private static var isAsking = false

    static func offerToOpen(_ url: URL, in window: NSWindow?) async {
        if let openerForTesting {
            openerForTesting(url)
            return
        }
        guard let host = window, !isAsking else { return }
        isAsking = true
        defer { isAsking = false }
        let match = await application(toOpen: url)
        let alert = NSAlert()

        guard let match else {
            alert.messageText = String(localized: "No app can open this link.")
            alert.informativeText = String(
                localized: "Nothing installed on this Mac handles “\(url.scheme ?? "")” links."
            )
            alert.addButton(withTitle: String(localized: "OK"))
            _ = await present(alert, in: host)
            return
        }

        alert.messageText = String(localized: "Do you want to allow this page to open “\(match.name)”?")
        alert.addButton(withTitle: String(localized: "Allow"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard await present(alert, in: host) == .alertFirstButtonReturn else { return }
        NSWorkspace.shared.open(url)
    }

    private nonisolated static func application(toOpen url: URL) async -> Match? {
        await Task.detached(priority: .userInitiated) {
            guard let app = NSWorkspace.shared.urlForApplication(toOpen: url) else { return nil }
            return Match(url: app, name: FileManager.default.displayName(atPath: app.path))
        }.value
    }

    private static func present(
        _ alert: NSAlert,
        in window: NSWindow?
    ) async -> NSApplication.ModalResponse {
        guard let window else { return .cancel }
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response)
            }
        }
    }
}
