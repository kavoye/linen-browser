// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@MainActor
struct ShellOverlaysTests {
    @Test func thePageIsCoveredWhileThePointerIsOnAnyCover() {
        let overlays = ShellOverlays()

        overlays.notePointer(on: .island, true)
        overlays.notePointer(on: .sidePanel, true)
        overlays.notePointer(on: .island, false)
        #expect(overlays.isPointerOnPageCover, "the side panel still covers the page")

        overlays.notePointer(on: .sidePanel, false)
        #expect(!overlays.isPointerOnPageCover)
    }

    @Test func onlyCoveringAndUncoveringThePageAreReported() {
        let overlays = ShellOverlays()
        var changes = 0
        overlays.onCoverChange = { changes += 1 }

        overlays.notePointer(on: .island, true)
        overlays.notePointer(on: .mediaCard, true)
        overlays.notePointer(on: .island, true)
        overlays.notePointer(on: .island, false)
        #expect(changes == 1, "moving between covers is not a change")

        overlays.notePointer(on: .mediaCard, false)
        #expect(changes == 2)
        overlays.notePointer(on: .question, false)
        #expect(changes == 2, "leaving a cover the pointer was never on changes nothing")
    }

    @Test func escapeClosesTheTabListOnlyWhenItIsOpen() {
        let overlays = ShellOverlays()

        #expect(!overlays.closeMinimalMenus())

        overlays.isTabListOpen = true
        #expect(overlays.closeMinimalMenus())
        #expect(!overlays.isTabListOpen)
    }
}
