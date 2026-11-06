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
        privateWindow.image = NSImage(systemSymbolName: "hand.raised", accessibilityDescription: nil)
        privateWindow.target = target
        privateWindow.tag = 1
        privateWindow.keyEquivalentModifierMask = []
        guard !opensPrivately else { return [privateWindow] }

        let window = NSMenuItem(
            title: String(localized: "Open Link in New Window"), action: action, keyEquivalent: ""
        )
        window.identifier = .init("LinenOpenLinkInNewWindow")
        window.image = NSImage(systemSymbolName: "macwindow.badge.plus", accessibilityDescription: nil)
        window.target = target
        window.keyEquivalentModifierMask = []
        privateWindow.isAlternate = true
        privateWindow.keyEquivalentModifierMask = .option
        return [window, privateWindow]
    }

    private static let symbols = [
        "WKMenuItemIdentifierCopy": "doc.on.doc",
        "WKMenuItemIdentifierCopyImage": "doc.on.doc",
        "WKMenuItemIdentifierCopyLinkWithHighlight": "doc.on.doc",
        "WKMenuItemIdentifierCopyMediaLink": "doc.on.doc",
        "WKMenuItemIdentifierCopySubject": "doc.on.doc",
        "WKMenuItemIdentifierDownloadImage": "arrow.down",
        "WKMenuItemIdentifierDownloadLinkedFile": "arrow.down",
        "WKMenuItemIdentifierDownloadMedia": "arrow.down",
        "WKMenuItemIdentifierGoBack": "chevron.left",
        "WKMenuItemIdentifierGoForward": "chevron.right",
        "WKMenuItemIdentifierInspectElement": "wrench.and.screwdriver",
        "WKMenuItemIdentifierLookUp": "text.magnifyingglass",
        "WKMenuItemIdentifierPaste": "doc.on.clipboard",
        "WKMenuItemIdentifierReload": "arrow.clockwise",
        "WKMenuItemIdentifierRevealImage": "photo.badge.magnifyingglass",
        "WKMenuItemIdentifierSearchWeb": "magnifyingglass",
        "WKMenuItemIdentifierShareMenu": "square.and.arrow.up",
        "WKMenuItemIdentifierSpeechMenu": "speaker.wave.2",
        "WKMenuItemIdentifierSpellingMenu": "textformat.abc.dottedunderline",
        "WKMenuItemIdentifierSubstitutionsMenu": "textformat",
        "WKMenuItemIdentifierToggleFullScreen": "arrow.up.left.and.arrow.down.right",
        "WKMenuItemIdentifierTogglePictureInPicture": "pip.enter",
        "WKMenuItemIdentifierTranslate": "translate",
    ]

    private static let replacedSymbols = [
        "WKMenuItemIdentifierCopyLink": "link",
        "WKMenuItemIdentifierOpenFrameInNewWindow": "plus.square",
        "WKMenuItemIdentifierOpenImageInNewWindow": "plus.square",
        "WKMenuItemIdentifierOpenLink": "arrow.up.right",
        "WKMenuItemIdentifierOpenLinkInNewWindow": "plus.square",
        "WKMenuItemIdentifierOpenMediaInNewWindow": "plus.square",
    ]

    private static let shortcuts = [
        "WKMenuItemIdentifierCopy": "c",
        "WKMenuItemIdentifierGoBack": "[",
        "WKMenuItemIdentifierGoForward": "]",
        "WKMenuItemIdentifierPaste": "v",
        "WKMenuItemIdentifierReload": "r",
    ]

    static func decorate(_ item: NSMenuItem, identifier: String) {
        if let symbol = replacedSymbols[identifier] ?? (item.image == nil ? symbols[identifier] : nil) {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        if item.keyEquivalent.isEmpty, let key = shortcuts[identifier] {
            item.keyEquivalent = key
            item.keyEquivalentModifierMask = .command
        }
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
