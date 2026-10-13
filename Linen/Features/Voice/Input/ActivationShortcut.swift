// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit

nonisolated struct ActivationShortcut: Equatable, Codable, Sendable {
    var keyCode: UInt16
    var modifierFlags: UInt
    var label: String

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags = [], label: String) {
        self.keyCode = keyCode
        self.modifierFlags = modifiers.rawValue
        self.label = label
    }

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlags)
    }

    var isModifierOnly: Bool {
        Self.modifierKeys[keyCode] != nil
    }

    var caps: [String] {
        isModifierOnly ? [label] : Self.glyphs(for: modifiers) + [label]
    }

    var phrase: String {
        caps.joined()
    }

    // MARK: - Refusals

    enum Refusal: Equatable {
        case bareKey
        case command
    }

    static func refusal(for shortcut: ActivationShortcut) -> Refusal? {
        guard !shortcut.isModifierOnly else {
            return modifierKeys[shortcut.keyCode]?.flag == .command ? .command : nil
        }
        if shortcut.modifiers.isEmpty {
            return .bareKey
        }
        return shortcut.modifiers.contains(.command) ? .command : nil
    }

    // MARK: - Matching

    func isDown(in flags: NSEvent.ModifierFlags) -> Bool {
        guard let flag = Self.modifierKeys[keyCode]?.flag else { return false }
        return flags.contains(flag)
    }

    func matches(_ event: NSEvent) -> Bool {
        event.keyCode == keyCode && Self.significant(event.modifierFlags) == modifiers
    }

    static func significant(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.command, .option, .control, .shift])
    }

    // MARK: - The keyboard

    static let optionSpace = ActivationShortcut(
        keyCode: 49,
        modifiers: .option,
        label: String(localized: "Space")
    )

    static let modifierKeys: [UInt16: (name: String, flag: NSEvent.ModifierFlags)] = [
        55: (String(localized: "left ⌘"), .command),
        54: (String(localized: "right ⌘"), .command),
        56: (String(localized: "left ⇧"), .shift),
        60: (String(localized: "right ⇧"), .shift),
        58: (String(localized: "left ⌥"), .option),
        61: (String(localized: "right ⌥"), .option),
        59: (String(localized: "left ⌃"), .control),
        62: (String(localized: "right ⌃"), .control),
        63: ("fn", .function),
    ]

    static func glyphs(for flags: NSEvent.ModifierFlags) -> [String] {
        var glyphs: [String] = []
        if flags.contains(.control) {
            glyphs.append("⌃")
        }
        if flags.contains(.option) {
            glyphs.append("⌥")
        }
        if flags.contains(.shift) {
            glyphs.append("⇧")
        }
        if flags.contains(.command) {
            glyphs.append("⌘")
        }
        return glyphs
    }

    private static let namedKeys: [UInt16: String] = [
        49: String(localized: "Space"), 36: String(localized: "Return"),
        76: String(localized: "Enter"), 48: String(localized: "Tab"),
        51: String(localized: "Delete"), 117: String(localized: "Fwd Del"),
        53: String(localized: "Esc"), 115: String(localized: "Home"),
        119: String(localized: "End"), 116: String(localized: "Page Up"),
        121: String(localized: "Page Down"),
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    static func label(for event: NSEvent) -> String {
        if let named = namedKeys[event.keyCode] {
            return named
        }
        if let typed = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines),
           !typed.isEmpty {
            return typed.uppercased()
        }
        return String(localized: "key \(event.keyCode)")
    }
}

nonisolated enum ActivationSettings {
    static let defaultTalk = ActivationShortcut.optionSpace

    static var talk: ActivationShortcut {
        get { read("input.shortcut.talk") ?? defaultTalk }
        set { write(newValue, "input.shortcut.talk") }
    }

    private static func read(_ key: String) -> ActivationShortcut? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ActivationShortcut.self, from: data)
    }

    private static func write(_ shortcut: ActivationShortcut, _ key: String) {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
