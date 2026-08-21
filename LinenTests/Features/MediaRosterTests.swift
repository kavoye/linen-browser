// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// Which tabs the dock may move to on its own, which ones the user may pick,
/// which tab owns the lyrics, and where a video goes when you leave.
struct MediaRosterTests {
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()

    @Test func aPlayingBackgroundTabIsACandidate() {
        #expect(MediaRoster.isCandidate(
            isPlayingAudio: true,
            isMuted: false,
            isInternalPage: false,
            isActive: false,
            isVisibleInSplit: false,
            isDocked: false
        ))
    }

    @Test func whatTheDockCannotDriveIsNotACandidate() {
        func candidate(
            active: Bool = false,
            muted: Bool = false,
            internalPage: Bool = false,
            visibleInSplit: Bool = false
        ) -> Bool {
            MediaRoster.isCandidate(
                isPlayingAudio: true,
                isMuted: muted,
                isInternalPage: internalPage,
                isActive: active,
                isVisibleInSplit: visibleInSplit,
                isDocked: false
            )
        }

        #expect(!candidate(active: true))
        #expect(!candidate(muted: true))
        #expect(!candidate(internalPage: true))
        #expect(!candidate(visibleInSplit: true))
    }

    @Test func theDockedTabKeepsItsPlaceWhilePaused() {
        #expect(MediaRoster.isCandidate(
            isPlayingAudio: false,
            isMuted: false,
            isInternalPage: false,
            isActive: false,
            isVisibleInSplit: false,
            isDocked: true
        ))
    }

    /// Muting a tab used to hand the dock to the next tab, and the media card
    /// went with it. Mute silences the tab; it does not undock it.
    @Test func theDockedTabKeepsItsPlaceWhileMuted() {
        #expect(MediaRoster.isCandidate(
            isPlayingAudio: true,
            isMuted: true,
            isInternalPage: false,
            isActive: false,
            isVisibleInSplit: false,
            isDocked: true
        ))
    }

    @Test func theTabInFrontGoesIntoThePictureFirst() {
        #expect(MediaRoster.pictureTarget(
            active: a, isActivePlaying: true, docked: b, isDockedPlaying: true
        ) == a)
    }

    @Test func theDockAnswersWhenTheTabInFrontPlaysNothing() {
        #expect(MediaRoster.pictureTarget(
            active: a, isActivePlaying: false, docked: b, isDockedPlaying: true
        ) == b)
    }

    @Test func nothingPausedIsSentOutOnItsOwn() {
        #expect(MediaRoster.pictureTarget(
            active: a, isActivePlaying: false, docked: b, isDockedPlaying: false
        ) == nil)
        #expect(MediaRoster.pictureTarget(
            active: a, isActivePlaying: false, docked: nil, isDockedPlaying: false
        ) == nil)
    }

    @Test func nothingIsTargetedWithoutATabInFrontOrADock() {
        #expect(MediaRoster.pictureTarget(
            active: nil, isActivePlaying: false, docked: nil, isDockedPlaying: false
        ) == nil)
    }

    @Test func aPausedTabThatIsNotDockedIsNotACandidate() {
        #expect(!MediaRoster.isCandidate(
            isPlayingAudio: false,
            isMuted: false,
            isInternalPage: false,
            isActive: false,
            isVisibleInSplit: false,
            isDocked: false
        ))
    }

    private func pickerItem(
        playing: Bool = false,
        muted: Bool = false,
        internalPage: Bool = false,
        active: Bool = false,
        visibleInSplit: Bool = false,
        docked: Bool = false,
        hasPlayed: Bool = false
    ) -> Bool {
        MediaRoster.isPickerItem(
            isPlayingAudio: playing,
            isMuted: muted,
            isInternalPage: internalPage,
            isActive: active,
            isVisibleInSplit: visibleInSplit,
            isDocked: docked,
            hasPlayed: hasPlayed
        )
    }

    /// Pausing a tab and moving on used to strand it: silent and undocked, it
    /// left the picker and could only be reached from the sidebar again.
    @Test func aTabThatPlayedAndFellQuietStaysInThePicker() {
        #expect(pickerItem(hasPlayed: true))
        #expect(!pickerItem(hasPlayed: false))
    }

    @Test func theDockedTabStaysInItsOwnPickerWhileMuted() {
        #expect(pickerItem(playing: true, muted: true, docked: true))
    }

    @Test func havingPlayedDoesNotOverrideWhatTheDockCannotDrive() {
        #expect(!pickerItem(muted: true, hasPlayed: true))
        #expect(!pickerItem(internalPage: true, hasPlayed: true))
        #expect(!pickerItem(active: true, hasPlayed: true))
        #expect(!pickerItem(visibleInSplit: true, hasPlayed: true))
    }

    @Test func whatIsPlayingIsInThePickerWhetherItPlayedBeforeOrNot() {
        #expect(pickerItem(playing: true, hasPlayed: false))
        #expect(pickerItem(docked: true, hasPlayed: false))
    }

    private func lyricsSource(
        playing: Bool = false,
        hasPlayed: Bool = false,
        internalPage: Bool = false,
        deferred: Bool = false
    ) -> Bool {
        MediaRoster.isLyricsSource(
            isPlayingAudio: playing,
            hasPlayed: hasPlayed,
            isInternalPage: internalPage,
            isDeferred: deferred
        )
    }

    @Test func pausingOrMutingKeepsTheWordsOnScreen() {
        #expect(lyricsSource(playing: false, hasPlayed: true))
    }

    @Test func aTabThatNeverPlayedHasNoWordsToShow() {
        #expect(!lyricsSource(playing: false, hasPlayed: false))
        #expect(lyricsSource(playing: true, hasPlayed: false))
    }

    @Test func aPageOfLinensOwnNeverCarriesLyrics() {
        #expect(!lyricsSource(playing: true, hasPlayed: true, internalPage: true))
        #expect(!lyricsSource(playing: true, hasPlayed: true, deferred: true))
    }

    private func owner(
        pinned: UUID? = nil,
        active: UUID? = nil,
        docked: UUID? = nil,
        candidates: [UUID]
    ) -> UUID? {
        MediaRoster.lyricsOwner(
            pinned: pinned,
            active: active,
            docked: docked,
            candidates: candidates
        )
    }

    @Test func theTabYouAreLookingAtBeatsTheDock() {
        #expect(owner(active: a, docked: b, candidates: [a, b]) == a)
    }

    @Test func theDockCarriesTheWordsWhenTheTabInFrontOfYouHasNoMedia() {
        #expect(owner(active: c, docked: b, candidates: [a, b]) == b)
        #expect(owner(active: nil, docked: b, candidates: [b]) == b)
    }

    @Test func pinningATabOverridesBothOfThem() {
        #expect(owner(pinned: b, active: a, docked: c, candidates: [a, b, c]) == b)
    }

    @Test func aPinOnATabThatStoppedFallsBackRatherThanEmptying() {
        #expect(owner(pinned: c, active: a, docked: b, candidates: [a, b]) == a)
    }

    @Test func nothingEligibleMeansNoWords() {
        #expect(owner(active: a, docked: b, candidates: []) == nil)
    }

    @Test func theSuccessorIsTheNextTabDownTheList() {
        #expect(MediaRoster.successor(to: a, in: [a, b, c]) == b)
        #expect(MediaRoster.successor(to: c, in: [a, b, c]) == a)
    }

    @Test func aTabAlreadyGoneHandsOverToTheTopOfTheList() {
        #expect(MediaRoster.successor(to: a, in: [b, c]) == b)
    }

    @Test func thereIsNoSuccessorWhenNothingElsePlays() {
        #expect(MediaRoster.successor(to: a, in: [a]) == nil)
        #expect(MediaRoster.successor(to: a, in: []) == nil)
    }
}
