// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Testing

@testable import Linen

@MainActor
struct SpaceAppearanceTests {
    @Test func everyOfferedSymbolExists() {
        let missing = SpaceAppearance.symbols.filter {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil
        }
        #expect(missing.isEmpty, "\(missing)")
    }

    @Test func theGridFillsWholeRows() {
        #expect(SpaceAppearance.symbols.count % 16 == 0)
        #expect(Set(SpaceAppearance.symbols).count == SpaceAppearance.symbols.count)
    }
}
