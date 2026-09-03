// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class PeekPanel {
    private(set) var tab: BrowserTab?

    /// The tab the peek was opened from. It stays with that page, so leaving
    /// for another tab hides the panel rather than closing it.
    private(set) var ownerID: UUID?

    /// Where the link was clicked, in the content area's own points.
    private(set) var origin: CGPoint = .zero

    /// A peek that is kept hands its page to the window behind it, so the
    /// panel must not shrink away empty.
    private(set) var isQuiet = false

    var isOpen: Bool {
        tab != nil
    }

    func show(_ tab: BrowserTab, from owner: UUID?, at origin: CGPoint) {
        self.tab = tab
        ownerID = owner
        self.origin = origin
        isQuiet = false
    }

    func aim(at origin: CGPoint) {
        self.origin = origin
    }

    func belongs(to tabID: UUID) -> Bool {
        ownerID == tabID
    }

    func take(quietly: Bool = false) -> BrowserTab? {
        let held = tab
        isQuiet = quietly
        tab = nil
        ownerID = nil
        return held
    }
}
