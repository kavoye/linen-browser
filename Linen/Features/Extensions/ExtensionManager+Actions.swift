// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import os
import WebKit

extension ExtensionManager {
    var actionableExtensions: [InstalledExtension] {
        (installed + systemExtensions).filter { $0.enabled && contexts[$0.id] != nil }
    }

    var pinnedExtensions: [InstalledExtension] {
        actionableExtensions.filter(\.isPinned)
    }

    var unpinnedExtensions: [InstalledExtension] {
        actionableExtensions.filter { !$0.isPinned }
    }

    func registerAnchor(_ view: NSView?, for id: String, in browser: BrowserModel) {
        guard adapter(for: browser) != nil else { return }
        popups.register(view, for: id, in: browser)
    }

    func registerOverflowAnchor(_ view: NSView?, in browser: BrowserModel) {
        guard adapter(for: browser) != nil else { return }
        popups.registerOverflow(view, in: browser)
    }

    func performAction(for id: String, in browser: BrowserModel? = nil) {
        guard let window = registeredWindow(in: browser), let context = contexts[id] else { return }
        let tab = window.browser?.activeTab.map { adapter(for: $0) }
        guard let action = context.action(for: tab) else { return }

        guard !popups.handlesRepeatClick(on: id) else { return }

        if action.presentsPopup {
            present(action, for: id, in: browser)
        } else {
            context.performAction(for: tab)
        }
    }
}
