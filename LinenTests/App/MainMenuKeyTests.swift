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

    /// ⌘N is New Window on macOS. Linen has one window, so the key is left
    /// alone rather than aliased to New Tab, which ⌘T already opens.
    @Test func commandNIsLeftToTheSystem() throws {
        let coordinator = AppCoordinator()
        let menu = MainMenu(coordinator: coordinator)
        menu.install()
        defer { NSApp.mainMenu = nil }
        let root = try #require(NSApp.mainMenu)

        let before = coordinator.browser.tabs.count
        #expect(!pressed("n", modifiers: .command, in: root))
        #expect(coordinator.browser.tabs.count == before)
    }

    /// ⇧⌘N is checked by what it is bound to rather than by pressing it.
    /// Private browsing is a profile now, and entering one repoints the shared
    /// web view pool, zoom store and permission store - a test that actually
    /// pressed the key would leave every test after it in private browsing.
    ///
    /// A real ⇧N keystroke carries "N", not "n": a lowercase character
    /// alongside a shift flag is an event no keyboard produces, and AppKit
    /// matches it to the wrong item. That is what the character below pins.
    @Test func shiftCommandNIsBoundToPrivateBrowsing() throws {
        let coordinator = AppCoordinator()
        let menu = MainMenu(coordinator: coordinator)
        menu.install()
        defer { NSApp.mainMenu = nil }
        let root = try #require(NSApp.mainMenu)

        let item = try #require(
            root.items
                .compactMap(\.submenu)
                .flatMap(\.items)
                .first { $0.title == String(localized: "Private Browsing") }
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

    /// Leaving has no key of its own, and is unavailable until there is a
    /// private session to leave.
    @Test func leavingPrivateBrowsingIsGreyUntilThereIsSomethingToLeave() throws {
        let coordinator = AppCoordinator()
        let menu = MainMenu(coordinator: coordinator)
        menu.install()
        defer { NSApp.mainMenu = nil }
        let root = try #require(NSApp.mainMenu)

        let item = try #require(
            root.items
                .compactMap(\.submenu)
                .flatMap(\.items)
                .first { $0.title == String(localized: "Leave Private Browsing") }
        )
        #expect(!menu.validateMenuItem(item))
    }
}
