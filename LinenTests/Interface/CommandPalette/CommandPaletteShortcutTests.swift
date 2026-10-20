// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Testing

@testable import Linen

@MainActor
@Suite(.boundedWebViews)
struct CommandPaletteShortcutTests {
    @Test func layoutStaysCentredAndRespectsNarrowWindowMargins() {
        let standard = CommandPaletteLayout(containerSize: CGSize(width: 1_200, height: 900))
        #expect(standard.panelWidth == 600)
        #expect(standard.maxListHeight == 420)
        #expect(standard.topInset == 209)

        let narrow = CommandPaletteLayout(containerSize: CGSize(width: 520, height: 300))
        #expect(narrow.panelWidth == 440)
        #expect(narrow.maxListHeight == 158)
        #expect(narrow.topInset == 40)
    }

    @Test func shortcutPolicyKeepsEditingAndPaletteCommandsOpen() {
        for key in ["a", "c", "v", "x", "z", "A"] {
            #expect(!CommandPaletteShortcutPolicy.shouldDismiss(modifiers: .command, key: key))
        }
        #expect(!CommandPaletteShortcutPolicy.shouldDismiss(modifiers: .command, key: "k"))
        #expect(!CommandPaletteShortcutPolicy.shouldDismiss(modifiers: .command, key: "t"))
        #expect(!CommandPaletteShortcutPolicy.shouldDismiss(modifiers: .shift, key: "p"))
        #expect(!CommandPaletteShortcutPolicy.shouldDismiss(modifiers: [], key: "p"))

        #expect(!CommandPaletteShortcutPolicy.shouldDismiss(modifiers: .control, key: "f"))
        #expect(!CommandPaletteShortcutPolicy.shouldDismiss(modifiers: .option, key: "p"))

        #expect(CommandPaletteShortcutPolicy.shouldDismiss(modifiers: .command, key: "l"))
        #expect(CommandPaletteShortcutPolicy.shouldDismiss(modifiers: .control, key: "\t"))
    }

    @Test(arguments: [
        NSEvent.ModifierFlags.capsLock,
        .numericPad,
        .function,
        [.capsLock, .numericPad, .function],
    ])
    func shortcutPolicyIgnoresFlagsThatDoNotChangeTheCommand(incidentalFlags: NSEvent.ModifierFlags) {
        for key in ["a", "c", "v", "x", "z", "V", "k", "t"] {
            #expect(!CommandPaletteShortcutPolicy.shouldDismiss(modifiers: [.command, incidentalFlags], key: key))
        }
        #expect(CommandPaletteShortcutPolicy.shouldDismiss(modifiers: [.command, incidentalFlags], key: "l"))
    }

    @Test func pasteAndMatchStyleAndRedoKeepThePaletteOpen() {
        for incidentalFlags: NSEvent.ModifierFlags in [[], .capsLock] {
            #expect(!CommandPaletteShortcutPolicy.shouldDismiss(
                modifiers: [.command, .option, .shift, incidentalFlags], key: "V"
            ))
            #expect(!CommandPaletteShortcutPolicy.shouldDismiss(
                modifiers: [.command, .shift, incidentalFlags], key: "Z"
            ))
            #expect(CommandPaletteShortcutPolicy.shouldDismiss(
                modifiers: [.command, .shift, incidentalFlags], key: "C"
            ))
        }
    }

    @Test func commandShortcutsUseTheCommandLayoutInsteadOfTheTypingLayout() {
        let keys = [
            (typing: "м", command: "v"),
            (typing: "с", command: "c"),
            (typing: "ч", command: "x"),
            (typing: "ф", command: "a"),
            (typing: "я", command: "z"),
            (typing: "л", command: "k"),
            (typing: "е", command: "t"),
            (typing: "k", command: "v"),
        ]
        for key in keys {
            #expect(!CommandPaletteShortcutPolicy.shouldDismiss(
                modifiers: .command, key: key.typing, commandKey: key.command
            ))
        }
        #expect(!CommandPaletteShortcutPolicy.shouldDismiss(
            modifiers: [.command, .option, .shift, .capsLock], key: "М", commandKey: "v"
        ))
        #expect(CommandPaletteShortcutPolicy.shouldDismiss(modifiers: .command, key: "в", commandKey: "l"))
        #expect(CommandPaletteShortcutPolicy.shouldDismiss(modifiers: [.command, .control], key: "f", commandKey: "v"))
    }

    @Test func paletteShortcutsToggleAndNewTabSelectionTracksThePalette() {
        let coordinator = AppCoordinator()
        let frameKey = "NSWindow Frame linen.browser.window.\(coordinator.windowID.uuidString)"
        let savedFrame = UserDefaults.standard.object(forKey: frameKey)
        defer {
            coordinator.closeWindow()
            UserDefaults.standard.set(savedFrame, forKey: frameKey)
        }
        let tab = coordinator.browser.newTab()
        coordinator.browser.sidebarSelection.toggle(.tab(tab.id))

        coordinator.togglePalette()
        #expect(coordinator.palette.isOpen)
        #expect(!coordinator.palette.isNewTab)
        let token = coordinator.palette.token

        coordinator.togglePalette()
        #expect(!coordinator.palette.isOpen)
        #expect(coordinator.palette.token == token)

        coordinator.requestNewTab()
        #expect(coordinator.palette.isOpen)
        #expect(coordinator.palette.isNewTab)
        #expect(coordinator.browser.sidebarSelection.isEmpty)
        #expect(coordinator.browser.tabs.count == 1)
        #expect(coordinator.palette.token == token + 1)

        coordinator.requestNewTab()
        #expect(!coordinator.palette.isOpen)
        #expect(!coordinator.palette.isNewTab)

        coordinator.requestNewTab()
        #expect(coordinator.palette.isNewTab)
        coordinator.togglePalette()
        #expect(!coordinator.palette.isOpen)
        #expect(!coordinator.palette.isNewTab)
    }

    /// A modified arrow is the palette moving its own selection. Dismissing on
    /// it is what took command-arrow section jumps away.
    @Test func aModifiedArrowStaysWithTheList() {
        let arrows = [NSUpArrowFunctionKey, NSDownArrowFunctionKey, NSLeftArrowFunctionKey, NSRightArrowFunctionKey]
            .compactMap { UnicodeScalar($0).map(String.init) }
        for key in arrows {
            #expect(!CommandPaletteShortcutPolicy.shouldDismiss(modifiers: .command, key: key))
            #expect(!CommandPaletteShortcutPolicy.shouldDismiss(modifiers: [], key: key))
            #expect(!CommandPaletteShortcutPolicy.shouldDismiss(modifiers: .option, key: key))
        }
    }

    @Test func lineAndWordEditingKeepsThePaletteOpen() {
        let backspace = "\u{7f}"
        let forwardDelete = String(UnicodeScalar(NSDeleteFunctionKey)!)
        let left = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        let right = String(UnicodeScalar(NSRightArrowFunctionKey)!)
        let edits: [(NSEvent.ModifierFlags, String)] = [
            (.command, backspace), (.option, backspace), (.control, backspace),
            (.option, forwardDelete), (.command, left), (.command, right),
            ([.command, .shift], left), ([.option, .shift], right),
        ]
        for (modifiers, key) in edits {
            #expect(!CommandPaletteShortcutPolicy.shouldDismiss(modifiers: modifiers, key: key))
        }
        #expect(CommandPaletteShortcutPolicy.shouldDismiss(modifiers: .command, key: "l"))
    }

    @Test func optionTypingAndControlEditingKeepThePaletteOpen() {
        let kept: [(NSEvent.ModifierFlags, String)] = [
            (.option, "e"), (.option, "l"), ([.option, .shift], "-"),
            (.control, "a"), (.control, "e"), (.control, "k"), ([.control, .option], "b"),
            ([.command, .control], " "),
        ]
        for (modifiers, key) in kept {
            #expect(!CommandPaletteShortcutPolicy.shouldDismiss(modifiers: modifiers, key: key))
        }
        #expect(CommandPaletteShortcutPolicy.shouldDismiss(modifiers: .control, key: "\t"))
        #expect(CommandPaletteShortcutPolicy.shouldDismiss(modifiers: [.control, .shift], key: "\t"))
        #expect(CommandPaletteShortcutPolicy.shouldDismiss(modifiers: [.command, .control], key: "f"))
    }

    @Test func commandArrowReachesAFocusedTextFieldBeforeBackAndForward() throws {
        let cases: [(modifiers: NSEvent.ModifierFlags, key: Int, expected: Bool)] = [
            (.command, NSLeftArrowFunctionKey, true),
            (.command, NSRightArrowFunctionKey, true),
            ([.command, .shift], NSLeftArrowFunctionKey, true),
            ([.command, .option], NSRightArrowFunctionKey, true),
            ([.command, .control], NSRightArrowFunctionKey, false),
            (.option, NSLeftArrowFunctionKey, false),
        ]
        for testCase in cases {
            let character = String(try #require(UnicodeScalar(testCase.key)))
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: testCase.modifiers.union([.function, .numericPad]),
                timestamp: 0, windowNumber: 0, context: nil,
                characters: character, charactersIgnoringModifiers: character,
                isARepeat: false, keyCode: 0
            ))
            #expect(ShortcutPriority.textEditorAnswersFirst(event) == testCase.expected)
        }
    }

    @Test func commandBackspaceReachesAFocusedTextField() throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}",
            isARepeat: false, keyCode: 51
        ))
        #expect(ShortcutPriority.textEditorAnswersFirst(event))
    }

    /// Command-arrow moves by section, and the sections it counts are the ones
    /// the palette is showing.
    @Test func commandArrowJumpsBetweenTheSectionsOnScreen() {
        var interaction = CommandPaletteInteraction(query: "org", selection: 0)
        let counts = [1, 0, 3, 2]

        interaction.moveSection(by: 1, itemCounts: counts)
        #expect(interaction.selection == 1)
        interaction.moveSection(by: 1, itemCounts: counts)
        #expect(interaction.selection == 4)
        interaction.moveSection(by: 1, itemCounts: counts)
        #expect(interaction.selection == 0)
        interaction.moveSection(by: -1, itemCounts: counts)
        #expect(interaction.selection == 4)
    }

    @Test func placeholderExplainsTheCurrentInputMode() {
        #expect(
            CommandPaletteProjection.placeholder(agentOnly: false)
                == String(localized: "Search tabs, history, actions, or the web")
        )
        #expect(
            CommandPaletteProjection.placeholder(agentOnly: true)
                == String(localized: "Search tabs, history, actions, or ask")
        )
    }
}
