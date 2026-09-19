// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation

@MainActor
enum MCPAccessConsent {
    enum Access: Sendable {
        case readOnly
        case control
    }

    struct Page: Equatable, Sendable {
        let id: UUID
        let title: String
        let url: URL
    }

    static func share(client: String, pages: [Page]) async -> Access? {
        guard !AppDatabase.isRunningTests else { return nil }
        let alert = NSAlert()
        let name = displayName(for: client)
        alert.messageText = pages.count == 1
            ? String(localized: "Allow \(name) to Access This Tab?")
            : String(localized: "Allow \(name) to Access These Tabs?")
        guard !pages.isEmpty else {
            alert.messageText = String(localized: "No Tab Available to Share")
            alert.informativeText = String(localized: "Open a webpage in Linen, then ask \(name) to try again.")
            alert.addButton(withTitle: String(localized: "OK"))
            _ = await present(alert)
            return nil
        }
        let names = pages.map { page in
            let title = page.title.count > 80 ? String(page.title.prefix(80)) + "…" : page.title
            return "\(title)\n\(page.url.host() ?? "")"
        }.joined(separator: "\n\n")
        let tabLabel = pages.count == 1
            ? String(localized: "Tab to share:")
            : String(localized: "Tabs to share:")
        alert.informativeText = String(localized: """
            \(tabLabel)
            \(names)

            Choose access:
            • Read Only: read page content.
            • Allow Control: also click, type, and navigate.
            """)
        alert.addButton(withTitle: String(localized: "Read Only"))
        alert.addButton(withTitle: String(localized: "Allow Control"))
        alert.addButton(withTitle: String(localized: "Don’t Allow"))
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        switch await present(alert) {
        case .alertFirstButtonReturn:
            return .readOnly
        case .alertSecondButtonReturn:
            return .control
        default:
            return nil
        }
    }

    static func open(client: String, url: URL) async -> Bool {
        guard !AppDatabase.isRunningTests else { return false }
        let alert = NSAlert()
        let name = displayName(for: client)
        alert.messageText = String(localized: "Open and Share This Website?")
        alert.informativeText = String(localized: """
            \(name) wants to open \(url.absoluteString).

            It will be able to read the page, click, type, and navigate.
            """)
        alert.addButton(withTitle: String(localized: "Open and Share"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        return await present(alert) == .alertFirstButtonReturn
    }

    private static func displayName(for client: String) -> String {
        client == "codex-mcp-client" ? "Codex" : client
    }

    private static func present(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        guard !Task.isCancelled else { return .abort }
        let window = NSApp.keyWindow ?? NSApp.mainWindow
            ?? NSApp.windows.first { $0.canBecomeMain && !($0 is NSPanel) }
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return await withTaskCancellationHandler {
            guard !Task.isCancelled else { return .abort }
            guard let window else { return alert.runModal() }
            return await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            }
        } onCancel: {
            Task { @MainActor in
                if let window {
                    window.endSheet(alert.window, returnCode: .abort)
                } else if NSApp.modalWindow === alert.window {
                    NSApp.abortModal()
                    alert.window.orderOut(nil)
                }
            }
        }
    }
}

@MainActor
final class MCPActionGrantStorage: AgentGrantStorage {
    var grantData: Data?
}
