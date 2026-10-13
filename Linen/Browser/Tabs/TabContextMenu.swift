// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit

@MainActor
enum TabContextMenu {
    static let inspectItem = "WKMenuItemIdentifierInspectElement"

    static func linkWindowItems(opensPrivately: Bool, target: AnyObject, action: Selector) -> [NSMenuItem] {
        let privateWindow = NSMenuItem(
            title: String(localized: "Open Link in New Private Window"), action: action, keyEquivalent: ""
        )
        privateWindow.identifier = .init("LinenOpenLinkInNewPrivateWindow")
        privateWindow.target = target
        privateWindow.tag = 1
        privateWindow.keyEquivalentModifierMask = []
        guard !opensPrivately else { return [privateWindow] }

        let window = NSMenuItem(
            title: String(localized: "Open Link in New Window"), action: action, keyEquivalent: ""
        )
        window.identifier = .init("LinenOpenLinkInNewWindow")
        window.target = target
        window.keyEquivalentModifierMask = []
        privateWindow.isAlternate = true
        privateWindow.keyEquivalentModifierMask = .option
        return [window, privateWindow]
    }

    static let linkTail = [
        "WKMenuItemIdentifierCopyLink",
        "WKMenuItemIdentifierShareMenu",
        "WKMenuItemIdentifierDownloadLinkedFile",
    ]

    static func sinkLinkTail(in menu: NSMenu) {
        let tail = linkTail.compactMap { identifier in
            menu.items.first { $0.identifier?.rawValue == identifier }
        }
        guard !tail.isEmpty else { return }
        for item in tail {
            menu.removeItem(item)
        }
        trimSeparators(in: menu)
        if !menu.items.isEmpty {
            menu.addItem(.separator())
        }
        for item in tail {
            menu.addItem(item)
        }
    }

    static func sinkInspect(in menu: NSMenu) {
        guard let item = menu.items.first(where: { $0.identifier?.rawValue == inspectItem }) else { return }
        let index = menu.index(of: item)
        menu.removeItem(item)
        if index > 0, menu.items[index - 1].isSeparatorItem {
            menu.removeItem(at: index - 1)
        }
        trimSeparators(in: menu)
        if !menu.items.isEmpty {
            menu.addItem(.separator())
        }
        menu.addItem(item)
    }

    private static func trimSeparators(in menu: NSMenu) {
        while menu.items.last?.isSeparatorItem == true {
            menu.removeItem(at: menu.numberOfItems - 1)
        }
    }
}
