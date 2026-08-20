// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import WebKit

@MainActor
enum PageDialogs {
    // MARK: - JavaScript dialogs

    static func alert(_ message: String, from frame: WKFrameInfo, in window: NSWindow?) async {
        guard let window else { return }
        let alert = makeAlert(message, from: frame)
        alert.addButton(withTitle: String(localized: "OK"))
        _ = await present(alert, in: window)
    }

    static func confirm(_ message: String, from frame: WKFrameInfo, in window: NSWindow?) async -> Bool {
        guard let window else { return false }
        let alert = makeAlert(message, from: frame)
        alert.addButton(withTitle: String(localized: "OK"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        return await present(alert, in: window) == .alertFirstButtonReturn
    }

    static func prompt(
        _ message: String,
        defaultText:
            String?,
        from frame: WKFrameInfo,
        in window: NSWindow?
    ) async -> String? {
        guard let window else { return nil }
        let alert = makeAlert(message, from: frame)
        alert.addButton(withTitle: String(localized: "OK"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        let field = NSTextField(string: defaultText ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard await present(alert, in: window) == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    // MARK: - File upload

    static func chooseFiles(
        _ parameters: WKOpenPanelParameters,
        in window: NSWindow?
    ) async -> [URL]? {
        guard let window else { return nil }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        return await withCheckedContinuation { continuation in
            panel.beginSheetModal(for: window) { response in
                continuation.resume(returning: response == .OK ? panel.urls : nil)
            }
        }
    }

    // MARK: - Building blocks

    private static func makeAlert(_ message: String, from frame: WKFrameInfo) -> NSAlert {
        let host = frame.securityOrigin.host
        let alert = NSAlert()
        alert.messageText = host.isEmpty
            ? String(localized: "A message from this page")
            : String(localized: "A message from “\(host)”")
        alert.informativeText = capped(message)
        return alert
    }

    static func capped(_ text: String, limit: Int = 1500) -> String {
        text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    private static func present(_ alert: NSAlert, in window: NSWindow) async -> NSApplication.ModalResponse {
        await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response)
            }
        }
    }
}
