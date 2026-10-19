// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation

@MainActor
enum MCPAccessConsent {
    static func approve(client: String, identity: MCPClientIdentity?) async -> Bool {
        await approve(client: client, identity: identity, in: NSApp.keyWindow ?? NSApp.mainWindow)
    }

    static func approve(client: String, identity: MCPClientIdentity?, in window: NSWindow?) async -> Bool {
        guard !AppDatabase.isRunningTests, let window else { return false }
        let alert = NSAlert()
        let name = displayName(for: client)
        alert.messageText = String(localized: "Allow “\(name)” to Use Linen?")
        let origin = identity?.developer.map { String(localized: "Verified developer: \($0).") }
            ?? String(localized: "Linen couldn’t verify who made this app.")
        let path = identity.map { "\n" + $0.path } ?? ""
        alert.informativeText = origin + path + "\n\n" + String(localized: """
            It can open tabs, and read and control websites using the same Assistant Access settings as Linen’s assistant. \
            Access ends when it disconnects.
            """)
        alert.addButton(withTitle: String(localized: "Allow"))
        alert.addButton(withTitle: String(localized: "Don’t Allow"))
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        return await present(alert, in: window) == .alertFirstButtonReturn
    }

    private static func displayName(for client: String) -> String {
        client == "codex-mcp-client" ? "Codex" : client
    }

    private static func present(_ alert: NSAlert, in window: NSWindow?) async -> NSApplication.ModalResponse {
        guard !Task.isCancelled else { return .abort }
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
