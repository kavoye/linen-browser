// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Testing

@testable import Linen

@MainActor
struct MenuItemImagesTests {
    private func item(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "pin", accessibilityDescription: nil)
        return item
    }

    @available(macOS 27, *)
    @Test func anAddedItemShowsItsImage() {
        let menu = NSMenu()
        let added = item("Added")
        menu.addItem(added)
        #expect(added.preferredImageVisibility == .visible)
    }

    @available(macOS 27, *)
    @Test func anInsertedItemShowsItsImage() {
        let menu = NSMenu()
        menu.addItem(item("Last"))
        let inserted = item("First")
        menu.insertItem(inserted, at: 0)
        #expect(inserted.preferredImageVisibility == .visible)
    }

    @available(macOS 27, *)
    @Test func anUpdatedItemKeepsShowingItsImage() {
        let menu = NSMenu()
        let updated = item("Before")
        menu.addItem(updated)
        updated.preferredImageVisibility = .automatic
        updated.title = "After"
        #expect(updated.preferredImageVisibility == .visible)
    }

    @Test func everyCommandInTheMenuBarHasAnIcon() throws {
        let coordinator = AppCoordinator()
        MainMenu(coordinator: coordinator).install()
        defer { NSApp.mainMenu = nil }
        let root = try #require(NSApp.mainMenu)

        var missing: [String] = []
        func walk(_ menu: NSMenu) {
            for item in menu.items where !item.isSeparatorItem && !item.isHidden {
                if item.image == nil {
                    missing.append(item.title)
                }
                if let submenu = item.submenu {
                    walk(submenu)
                }
            }
        }
        for item in root.items {
            if let submenu = item.submenu {
                walk(submenu)
            }
        }
        #expect(missing.isEmpty, "No icon: \(missing)")
    }

    @Test func aPageMenuItemGainsItsIconAndShortcut() {
        let item = NSMenuItem(title: "Reload Page", action: nil, keyEquivalent: "")
        TabContextMenu.decorate(item, identifier: "WKMenuItemIdentifierReload")
        #expect(item.image != nil)
        #expect(item.keyEquivalent == "r")
        #expect(item.keyEquivalentModifierMask == .command)
    }

    @Test func theOpenLinkItemsReplaceTheIconsWebKitGaveThem() {
        let original = NSImage(systemSymbolName: "safari", accessibilityDescription: nil)
        for identifier in ["WKMenuItemIdentifierOpenLink", "WKMenuItemIdentifierOpenLinkInNewWindow", "WKMenuItemIdentifierCopyLink"] {
            let item = NSMenuItem(title: "Link", action: nil, keyEquivalent: "")
            item.image = original
            TabContextMenu.decorate(item, identifier: identifier)
            #expect(item.image !== original)
        }
    }

    @Test func aPageMenuItemKeepsAnIconWebKitGaveIt() {
        let image = NSImage(systemSymbolName: "pin", accessibilityDescription: nil)
        let item = NSMenuItem(title: "Copy", action: nil, keyEquivalent: "")
        item.image = image
        TabContextMenu.decorate(item, identifier: "WKMenuItemIdentifierCopy")
        #expect(item.image === image)
    }
}
