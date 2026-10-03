// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Testing

@testable import Linen

@MainActor
struct CommandPaletteShortcutTests {
    @Test(arguments: [
        NSEvent.ModifierFlags.command,
        [.command, .capsLock],
        [.command, .option, .shift],
        [.command, .option, .shift, .capsLock],
    ])
    func pasteEventKeepsThePaletteOpenAndReachesTheEditor(modifiers: NSEvent.ModifierFlags) throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        try #require(board.setString("https://example.com/pasted", forType: .string))
        let editor = PasteEditor(frame: .zero)
        editor.pasteboard = board

        let previousMenu = NSApp.mainMenu
        let mainMenu = MainMenu(coordinator: AppCoordinator())
        mainMenu.install()
        defer { NSApp.mainMenu = previousMenu }
        let root = try #require(NSApp.mainMenu)
        for item in root.items.compactMap(\.submenu).flatMap(\.items)
        where item.action == #selector(NSText.paste(_:)) || item.action == #selector(NSTextView.pasteAsPlainText(_:)) {
            item.target = editor
        }

        let event = try pasteEvent(modifiers: modifiers)
        try #require(!CommandPaletteShortcutPolicy.shouldDismiss(event))
        #expect(root.performKeyEquivalent(with: event))
        #expect(editor.string == "https://example.com/pasted")
    }

    @Test func nativeEventTranslationRecognizesTheCommandCharacter() throws {
        let event = try pasteEvent(modifiers: .command, typingCharacter: "м")
        #expect(event.charactersIgnoringModifiers == "м")
        #expect(event.characters(byApplyingModifiers: .command)?.lowercased() == "v")
        #expect(!CommandPaletteShortcutPolicy.shouldDismiss(event))
    }

    private func pasteEvent(
        modifiers: NSEvent.ModifierFlags,
        typingCharacter: String? = nil
    ) throws -> NSEvent {
        // Find V in the current Command layout without changing the input source.
        for keyCode in UInt16(0)..<128 {
            let probe = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: 0, windowNumber: 0, context: nil,
                characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: keyCode
            ))
            guard probe.characters(byApplyingModifiers: .command)?.lowercased() == "v" else { continue }
            let characters = try #require(probe.characters(byApplyingModifiers: modifiers))
            let typing = try #require(typingCharacter ?? probe.characters(byApplyingModifiers: modifiers.intersection(.shift)))
            return try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: 0, context: nil,
                characters: characters, charactersIgnoringModifiers: typing,
                isARepeat: false, keyCode: keyCode
            ))
        }
        throw MissingPasteKey()
    }

    private struct MissingPasteKey: Error {}

    private final class PasteEditor: NSTextView {
        var pasteboard: NSPasteboard?

        override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
            // Native validation checks the general clipboard; this editor uses a private one.
            if item.action == #selector(paste(_:)) || item.action == #selector(pasteAsPlainText(_:)) {
                return pasteboard?.availableType(from: [.string]) != nil
            }
            return super.validateUserInterfaceItem(item)
        }

        override func paste(_ sender: Any?) {
            if let pasteboard {
                _ = readSelection(from: pasteboard, type: .string)
            }
        }

        override func pasteAsPlainText(_ sender: Any?) {
            paste(sender)
        }
    }
}
