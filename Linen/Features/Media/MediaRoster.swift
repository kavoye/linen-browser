// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

enum MediaRoster {
    static func isCandidate(
        isPlayingAudio: Bool,
        isMuted: Bool,
        isInternalPage: Bool,
        isActive: Bool,
        isVisibleInSplit: Bool,
        isDocked: Bool
    ) -> Bool {
        guard !isInternalPage, !isActive, !isVisibleInSplit else { return false }
        if isDocked {
            return true
        }
        return isPlayingAudio && !isMuted
    }

    static func isPickerItem(
        isPlayingAudio: Bool,
        isMuted: Bool,
        isInternalPage: Bool,
        isActive: Bool,
        isVisibleInSplit: Bool,
        isDocked: Bool,
        hasPlayed: Bool
    ) -> Bool {
        isCandidate(
            isPlayingAudio: isPlayingAudio || hasPlayed,
            isMuted: isMuted,
            isInternalPage: isInternalPage,
            isActive: isActive,
            isVisibleInSplit: isVisibleInSplit,
            isDocked: isDocked
        )
    }

    static func isLyricsSource(
        isPlayingAudio: Bool,
        hasPlayed: Bool,
        isInternalPage: Bool,
        isDeferred: Bool
    ) -> Bool {
        guard !isInternalPage, !isDeferred else { return false }
        return isPlayingAudio || hasPlayed
    }

    static func lyricsOwner(
        pinned: UUID?,
        active: UUID?,
        docked: UUID?,
        held: UUID? = nil,
        candidates: [UUID]
    ) -> UUID? {
        for choice in [pinned, active, held, docked] {
            if let choice, candidates.contains(choice) {
                return choice
            }
        }
        return nil
    }

    static func pictureTarget(
        active: UUID?,
        isActivePlaying: Bool,
        docked: UUID?,
        isDockedPlaying: Bool
    ) -> UUID? {
        if let active, isActivePlaying {
            return active
        }
        return isDockedPlaying ? docked : nil
    }

    static func successor(to previous: UUID, in roster: [UUID]) -> UUID? {
        guard let index = roster.firstIndex(of: previous) else { return roster.first }
        guard roster.count > 1 else { return nil }
        return roster[(index + 1) % roster.count]
    }
}
