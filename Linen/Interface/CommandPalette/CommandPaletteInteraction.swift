// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Observation
import WebKit

struct CommandPaletteInteraction: Equatable {
    var query = "" {
        didSet {
            if query != oldValue {
                selection = 0
            }
        }
    }
    var selection = 0

    mutating func moveSelection(by delta: Int, resultCount: Int) {
        selection = OmniboxSelection.moved(from: selection, by: delta, resultCount: resultCount)
    }

    mutating func moveSection(by delta: Int, itemCounts: [Int]) {
        selection = OmniboxSelection.movedBySection(from: selection, by: delta, itemCounts: itemCounts)
    }

    mutating func clampSelection(to resultCount: Int) {
        guard resultCount > 0 else {
            selection = 0
            return
        }
        selection = min(max(selection, 0), resultCount - 1)
    }
}

struct CommandPaletteLayout: Equatable {
    static let fieldHeight: CGFloat = 62
    static let margin: CGFloat = 40

    let containerSize: CGSize

    var maxListHeight: CGFloat {
        min(420, max(120, containerSize.height - Self.fieldHeight - Self.margin * 2))
    }

    var topInset: CGFloat {
        max(Self.margin, (containerSize.height - Self.fieldHeight - maxListHeight) / 2)
    }

    var panelWidth: CGFloat {
        let preferred = min(max(containerSize.width * 0.5, 480), 680)
        return min(preferred, max(containerSize.width - Self.margin * 2, 0))
    }
}

enum CommandPaletteShortcutPolicy {
    static let returnKeys: Set<String> = ["\r", "\u{3}"]

    static func showsCurrentTab(modifiers: NSEvent.ModifierFlags) -> Bool {
        let actionModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        return modifiers.intersection(actionModifiers) == .option
    }

    static func opensInCurrentTab(modifiers: NSEvent.ModifierFlags, key: String) -> Bool {
        showsCurrentTab(modifiers: modifiers) && returnKeys.contains(key)
    }

    static func shouldDismiss(_ event: NSEvent) -> Bool {
        let commandKey = event.modifierFlags.contains(.command)
            ? event.characters(byApplyingModifiers: .command)
            : nil
        return shouldDismiss(
            modifiers: event.modifierFlags,
            key: event.charactersIgnoringModifiers ?? "",
            commandKey: commandKey
        )
    }

    static func shouldDismiss(modifiers: NSEvent.ModifierFlags, key: String, commandKey: String? = nil) -> Bool {
        // Caps Lock and key-type flags do not change an editing shortcut.
        let modifiers = modifiers.intersection([.command, .control, .option, .shift])
        let editingKeys: Set<String> = ["a", "c", "v", "x", "z"]
        // Some layouts use different letters while Command is held.
        let normalizedKey = (modifiers.contains(.command) ? commandKey ?? key : key).lowercased()
        let isTextEditing = modifiers == .command && editingKeys.contains(normalizedKey)
            || modifiers == [.command, .shift] && normalizedKey == "z"
            || modifiers == [.command, .option, .shift] && normalizedKey == "v"
        let isPaletteShortcut = modifiers == .command && (normalizedKey == "k" || normalizedKey == "t")
        let isCaretEditing = ShortcutPriority.textEditingKeys.contains(key)
        let isRun = returnKeys.contains(key)
        let isCharacterPalette = modifiers == [.command, .control] && key == " "
        let isTyping = !modifiers.contains(.command) && (!modifiers.contains(.control) || key != "\t")
        return !isTyping && !isTextEditing && !isPaletteShortcut && !isCaretEditing && !isRun && !isCharacterPalette
    }
}
