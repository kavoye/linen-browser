// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Testing

@testable import Linen

/// Key equivalents through AppKit's own dispatch, not a direct selector
/// call: `performKeyEquivalent(with:)` is exactly what the app does with a
/// keystroke, so a hidden item that AppKit would skip fails here too. This
/// is the test that catches `allowsKeyEquivalentWhenHidden` being lost -
/// without it every hidden alias (⌘=, ⌘1-9, ⌃Tab) beeps.
@MainActor
struct MainMenuKeyTests {
    private func pressed(_ character: String, modifiers: NSEvent.ModifierFlags, in menu: NSMenu) -> Bool {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: 0
        ) else { return false }
        return menu.performKeyEquivalent(with: event)
    }

    @Test func aHiddenAliasStillAnswersItsKey() throws {
        let coordinator = AppCoordinator()
        let menu = MainMenu(coordinator: coordinator)
        menu.install()
        defer { NSApp.mainMenu = nil }
        let root = try #require(NSApp.mainMenu)

        #expect(pressed("=", modifiers: .command, in: root), "⌘= is the hidden alias for Zoom In")
    }

    @Test func commandNIsBoundToNewWindow() throws {
        let coordinator = AppCoordinator()
        let menu = MainMenu(coordinator: coordinator)
        menu.install()
        defer { NSApp.mainMenu = nil }
        let root = try #require(NSApp.mainMenu)
        let item = try #require(root.items.compactMap(\.submenu).flatMap(\.items)
            .first { $0.title == String(localized: "New Window") })

        #expect(item.keyEquivalent == "n")
        #expect(item.keyEquivalentModifierMask == [.command])
        #expect(menu.validateMenuItem(item))
    }

    // Shift-letter shortcuts use the uppercase character in AppKit's menu matching.
    @Test func shiftCommandNIsBoundToNewPrivateWindow() throws {
        let coordinator = AppCoordinator()
        let menu = MainMenu(coordinator: coordinator)
        menu.install()
        defer { NSApp.mainMenu = nil }
        let root = try #require(NSApp.mainMenu)

        let item = try #require(
            root.items
                .compactMap(\.submenu)
                .flatMap(\.items)
                .first { $0.title == String(localized: "New Private Window") }
        )
        // The shift belongs in the character, not the mask. A lowercase "n"
        // with `.shift` in the mask displays correctly and never matches a
        // keystroke, which is how every ⇧⌘-letter item here was once dead.
        #expect(item.keyEquivalent == "N")
        #expect(item.keyEquivalentModifierMask == [.command])
        #expect(item.isEnabled)
    }

    private func event(_ character: String, modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: 0
        ))
    }

    /// A site that calls `preventDefault` on every keydown - hackertyper.com
    /// is the one people meet - reports ⌘R, ⌘T and ⌘K as handled, and the
    /// views are offered a key equivalent before the main menu.
    @Test func browserCommandsOutrankThePage() throws {
        for key in ["r", "t", "k", "l", "w", "y", "["] {
            #expect(ShortcutPriority.menuAnswersFirst(try event(key, modifiers: .command)))
        }
        #expect(ShortcutPriority.menuAnswersFirst(try event("T", modifiers: [.command, .shift])))
        #expect(ShortcutPriority.menuAnswersFirst(try event("C", modifiers: [.command, .shift])))
        #expect(ShortcutPriority.menuAnswersFirst(try event("\t", modifiers: .control)))
    }

    /// Editing and find act on what is focused, so a page keeps them: web
    /// editors carry their own undo and their own find.
    @Test func editingAndFindStayWithThePage() throws {
        for key in ["z", "x", "c", "v", "a", "f", "g"] {
            #expect(!ShortcutPriority.menuAnswersFirst(try event(key, modifiers: .command)))
        }
        for key in [NSLeftArrowFunctionKey, NSRightArrowFunctionKey] {
            let arrow = String(UnicodeScalar(key)!)
            #expect(!ShortcutPriority.menuAnswersFirst(try event(arrow, modifiers: .command)))
        }
        #expect(!ShortcutPriority.menuAnswersFirst(try event("Z", modifiers: [.command, .shift])))
        #expect(!ShortcutPriority.menuAnswersFirst(try event("G", modifiers: [.command, .shift])))
    }

    /// A plain keystroke is not a key equivalent; nothing about its route
    /// changes.
    @Test func typingIsUntouched() throws {
        #expect(!ShortcutPriority.menuAnswersFirst(try event("a", modifiers: [])))
        #expect(!ShortcutPriority.menuAnswersFirst(try event("A", modifiers: .shift)))
    }

    @Test func privateWindowsUseTheNormalCloseWindowCommand() throws {
        let coordinator = AppCoordinator()
        let menu = MainMenu(coordinator: coordinator)
        menu.install()
        defer { NSApp.mainMenu = nil }
        let root = try #require(NSApp.mainMenu)
        let items = root.items.compactMap(\.submenu).flatMap(\.items)
        #expect(!items.contains { $0.title == String(localized: "Leave Private Browsing") })
        #expect(items.contains { $0.title == String(localized: "Close Window") })
    }

    @Test func windowCommandsStayAvailableWithoutAnOpenBrowserWindow() throws {
        let app = BrowserApplication()
        let menu = MainMenu(application: app)
        menu.install()
        defer { NSApp.mainMenu = nil }
        let root = try #require(NSApp.mainMenu)
        let items = root.items.compactMap(\.submenu).flatMap(\.items)

        for title in [String(localized: "New Window"), String(localized: "New Private Window")] {
            let item = try #require(items.first { $0.title == title })
            #expect(menu.validateMenuItem(item))
        }
        let reopen = try #require(items.first { $0.title == String(localized: "Reopen Last Closed Window") })
        #expect(menu.validateMenuItem(reopen) == app.canReopenWindow)
        #expect(app.windows.isEmpty, "Validating a menu must not create a browser window")
    }

    @Test(.boundedWebViews) func commandsActOnTheFocusedWindow() throws {
        let app = BrowserApplication()
        let context = BrowserProfileContext.shared(for: .original())
        let first = AppCoordinator(browser: BrowserModel(context: context, windowID: UUID()))
        let second = AppCoordinator(browser: BrowserModel(context: context, windowID: UUID()))
        app.register(first)
        app.register(second)
        let firstTab = first.browser.newTab()
        let secondTab = second.browser.newTab()
        let menu = MainMenu(application: app)
        menu.install()
        defer {
            NSApp.mainMenu = nil
            first.closeWindow()
            second.closeWindow()
        }
        let root = try #require(NSApp.mainMenu)
        app.focus(second)
        #expect(pressed("w", modifiers: .command, in: root))
        #expect(secondTab.isClosed)
        #expect(!firstTab.isClosed)
        #expect(first.browser.activeTab === firstTab)
    }
}
