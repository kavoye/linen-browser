// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import Observation

enum PageCover {
    case island
    case sidePanel
    case mediaCard
    case tabList
    case question
}

@Observable
final class ShellOverlays {
    var isProfileSwitcherOpen = false
    var profileButtonFrame: CGRect?
    var isTabListOpen = false

    private var pointerCovers: Set<PageCover> = []
    @ObservationIgnored var onCoverChange: () -> Void = {}

    var isPointerOnPageCover: Bool {
        !pointerCovers.isEmpty
    }

    func notePointer(on cover: PageCover, _ inside: Bool) {
        let before = pointerCovers
        if inside {
            pointerCovers.insert(cover)
        } else {
            pointerCovers.remove(cover)
        }
        guard pointerCovers.isEmpty != before.isEmpty else { return }
        onCoverChange()
    }

    func closeMinimalMenus() -> Bool {
        guard isTabListOpen else { return false }
        isTabListOpen = false
        return true
    }
}
