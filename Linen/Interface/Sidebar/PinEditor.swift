// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit

@MainActor
enum PinEditor {
    static func edit(_ tab: BrowserTab, in browser: BrowserModel) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Edit the pinned page")
        alert.informativeText = String(localized: "The tab returns to this address.")
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
        field.stringValue = tab.pinnedURL?.absoluteString ?? tab.urlString
        field.placeholderString = String(localized: "Address")
        field.lineBreakMode = .byTruncatingTail
        alert.accessoryView = field

        Task {
            let response: NSApplication.ModalResponse
            if let window = NSApp.keyWindow {
                alert.window.initialFirstResponder = field
                response = await withCheckedContinuation { continuation in
                    alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
                }
            } else {
                alert.window.initialFirstResponder = field
                response = alert.runModal()
            }
            guard response == .alertFirstButtonReturn else { return }
            guard let url = Omnibox.location(for: field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
            else { return }
            browser.setPin(url, for: tab)
        }
    }
}
