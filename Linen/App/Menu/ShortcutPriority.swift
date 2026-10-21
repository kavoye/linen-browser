// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit

@MainActor
enum ShortcutPriority {
    private static let leftArrow = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
    private static let rightArrow = String(UnicodeScalar(NSRightArrowFunctionKey)!)

    private static let pageFirst: [(key: String, modifiers: NSEvent.ModifierFlags)] = [
        ("z", [.command]),
        ("z", [.command, .shift]),
        ("x", [.command]),
        ("c", [.command]),
        ("v", [.command]),
        ("v", [.command, .option, .shift]),
        ("a", [.command]),
        ("f", [.command]),
        ("g", [.command]),
        ("g", [.command, .shift]),
        (leftArrow, [.command]),
        (rightArrow, [.command]),
    ]

    static let textEditingKeys: Set<String> = Set(
        [
            NSLeftArrowFunctionKey, NSRightArrowFunctionKey, NSUpArrowFunctionKey, NSDownArrowFunctionKey,
            NSHomeFunctionKey, NSEndFunctionKey, NSPageUpFunctionKey, NSPageDownFunctionKey, NSDeleteFunctionKey,
        ]
            .compactMap { UnicodeScalar($0).map(String.init) } + ["\u{7f}"]
    )

    static func textEditorAnswersFirst(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        guard flags.contains(.command), flags.isSubset(of: [.command, .option, .shift]) else { return false }
        return textEditingKeys.contains(event.charactersIgnoringModifiers ?? "")
    }

    static func menuAnswersFirst(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        guard flags.contains(.command) || flags.contains(.control) else { return false }
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        return !pageFirst.contains { $0.key == key && $0.modifiers == flags }
    }
}
