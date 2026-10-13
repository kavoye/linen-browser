// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

@Observable
final class MediaDockState {
    private(set) var claim = 0
    private var playedPages: [UUID: String] = [:]
    var lyricsPinnedTabID: UUID?
    var lyricsHeldTabID: UUID?

    @discardableResult
    func newClaim() -> Int {
        claim += 1
        return claim
    }

    func notePlayed(_ tabID: UUID, page: String) {
        playedPages[tabID] = page
    }

    func hasPlayed(_ tabID: UUID, page: String) -> Bool {
        playedPages[tabID] == page
    }

    func forget(_ tabID: UUID) {
        playedPages[tabID] = nil
    }
}
