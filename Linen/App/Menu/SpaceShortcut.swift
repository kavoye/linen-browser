// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit

enum SpaceShortcut {
    static let slots = 1...9
    static let modifiers: NSEvent.ModifierFlags = [.control]

    static func label(at index: Int) -> String? {
        slots.contains(index + 1) ? "⌃\(index + 1)" : nil
    }
}
