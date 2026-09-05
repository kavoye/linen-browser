// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit

@MainActor
enum TabContextMenu {
    static let inspectItem = "WKMenuItemIdentifierInspectElement"

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
