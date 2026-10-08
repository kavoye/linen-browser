// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import QuartzCore
import Testing

@testable import Linen

private struct StubCatalog: LyricsSource {
    var best: LyricsMatch?
    var found: [LyricsMatch] = []
    var others: [LyricsMatch] = []

    func lyrics(for queries: [LyricsQuery]) async -> LyricsFetch {
        LyricsFetch(best: best, alternatives: found)
    }

    func alternatives(for query: LyricsQuery) async -> [LyricsMatch] {
        others
    }
}

private func scratchDefaults() -> UserDefaults {
    UserDefaults(suiteName: TestDefaults.name("lyrics-tests"))!
}

private func match(
    id: Int = 1,
    synced: String = "[00:00.00] one\n[00:10.00] two\n[00:20.00] three",
    plain: String = "one\ntwo\nthree",
    instrumental: Bool = false
) -> LyricsMatch {
    LyricsMatch(
        id: id,
        track: "Something About Us",
        artist: "Daft Punk",
        album: "Discovery",
        duration: 233,
        synced: synced,
        plain: plain,
        isInstrumental: instrumental
    )
}

private func signature(
    isEnabled: Bool = true,
    isPrivate: Bool = false,
    isLive: Bool = false,
    title: String = "Something About Us",
    seconds: Int = 233
) -> LyricsSignature {
    LyricsSignature(
        tabID: UUID(),
        title: title,
        artist: "Daft Punk",
        album: "Discovery",
        seconds: seconds,
        isEnabled: isEnabled,
        isPrivate: isPrivate,
        isLive: isLive
    )
}

@MainActor
struct LyricsModelTests {
    @Test func tickingRequiresVisibleSyncedLyricsAndActivePlayback() async throws {
        let clock = TestClock()
        let model = LyricsModel(source: StubCatalog(best: match()), defaults: scratchDefaults(), clock: clock)
        model.isOnScreen = true
        model.sync(time: 0, isPlaying: true)
        #expect(clock.pendingCount == 0)

        await model.load(signature())
        try #require(await waitUntil { clock.pendingCount == 1 })
        model.sync(time: 5, isPlaying: false)
        #expect(await waitUntil { clock.pendingCount == 0 })

        model.sync(time: 5, isPlaying: true)
        try #require(await waitUntil { clock.pendingCount == 1 })
        model.isOnScreen = false
        #expect(await waitUntil { clock.pendingCount == 0 })

        model.isOnScreen = true
        try #require(await waitUntil { clock.pendingCount == 1 })
        model.use(match(synced: ""))
        #expect(await waitUntil { clock.pendingCount == 0 })
    }

    @Test func releasingLyricsCancelsItsPendingTick() async throws {
        let clock = TestClock()
        weak var released: LyricsModel?
        do {
            let model = LyricsModel(source: StubCatalog(best: match()), defaults: scratchDefaults(), clock: clock)
            released = model
            await model.load(signature())
            model.isOnScreen = true
            model.sync(time: 0, isPlaying: true)
            try #require(await waitUntil { clock.pendingCount == 1 })
        }
        #expect(await waitUntil { released == nil && clock.pendingCount == 0 })
    }

    @Test func aFoundTrackBecomesTimedLines() async {
        let model = LyricsModel(source: StubCatalog(best: match()), defaults: scratchDefaults())

        await model.load(signature())

        #expect(model.isSynced)
        #expect(model.lines.map(\.text) == ["one", "two", "three"])
        #expect(model.matched?.id == 1)
    }

    @Test func aPrivateTabIsNeverLookedUp() async {
        let model = LyricsModel(source: StubCatalog(best: match()), defaults: scratchDefaults())

        await model.load(signature(isPrivate: true))

        #expect(model.phase == .idle)
        #expect(model.matched == nil)
    }

    @Test func nothingIsLookedUpWhileTheSettingIsOff() async {
        let model = LyricsModel(source: StubCatalog(best: match()), defaults: scratchDefaults())

        await model.load(signature(isEnabled: false))

        #expect(model.phase == .off, "and it says so rather than looking empty")
        #expect(model.matched == nil)
    }

    @Test func aLiveStreamIsNeverLookedUp() async {
        let model = LyricsModel(source: StubCatalog(best: match()), defaults: scratchDefaults())

        await model.load(signature(isLive: true))

        #expect(model.phase == .live, "a stream is playing, so it is not “Nothing is playing”")
    }

    @Test func aTrackOfUnknownLengthWaitsForOne() async {
        let model = LyricsModel(source: StubCatalog(best: match()), defaults: scratchDefaults())

        await model.load(signature(seconds: 0))

        #expect(model.phase == .looking, "a track still filling in is not “Nothing is playing”")
    }

    @Test func noTabMeansNothingIsPlaying() async {
        let model = LyricsModel(source: StubCatalog(best: match()), defaults: scratchDefaults())
        var empty = signature(title: "", seconds: 0)
        empty.tabID = nil

        await model.load(empty)

        #expect(model.phase == .idle)
    }

    @Test func nothingFoundReportsItPlainly() async {
        let model = LyricsModel(source: StubCatalog(best: nil), defaults: scratchDefaults())

        await model.load(signature())

        #expect(model.phase == .missing)
        #expect(!model.isSynced)
    }

    @Test func anUnnamedTrackIsNotSentAnywhere() async {
        let model = LyricsModel(source: StubCatalog(best: match()), defaults: scratchDefaults())

        await model.load(signature(title: "(Official Video)"))

        #expect(model.phase == .missing)
    }

    @Test func anInstrumentalSaysSoRatherThanShowingWords() async {
        let model = LyricsModel(source: StubCatalog(best: match(instrumental: true)), defaults: scratchDefaults())

        await model.load(signature())

        #expect(model.phase == .instrumental)
        #expect(model.lines.isEmpty)
    }

    @Test func aTrackWithoutTimingsFallsBackToPlainWords() async {
        let model = LyricsModel(source: StubCatalog(best: match(synced: "")), defaults: scratchDefaults())

        await model.load(signature())

        #expect(!model.isSynced)
        #expect(model.plainText == "one\ntwo\nthree")
    }

    // MARK: - Following playback

    @Test func theActiveLineFollowsTheClock() async {
        let model = LyricsModel(source: StubCatalog(best: match()), defaults: scratchDefaults())
        await model.load(signature())

        model.sync(time: 0, isPlaying: false)
        #expect(model.activeIndex == 0)

        model.sync(time: 12, isPlaying: false)
        #expect(model.activeIndex == 1)

        model.sync(time: 25, isPlaying: false)
        #expect(model.activeIndex == 2)
    }

    @Test func timeRunsOnBetweenReportsWhilePlaying() {
        let model = LyricsModel(source: StubCatalog(), defaults: scratchDefaults())
        let host = CACurrentMediaTime()

        model.sync(time: 30, isPlaying: true)

        #expect(abs(model.elapsed(at: host + 2) - 32) < 0.05)
    }

    @Test func timeHoldsStillWhilePaused() {
        let model = LyricsModel(source: StubCatalog(), defaults: scratchDefaults())
        let host = CACurrentMediaTime()

        model.sync(time: 30, isPlaying: false)

        #expect(abs(model.elapsed(at: host + 2) - 30) < 0.05)
    }

    @Test func nudgingMovesTheWholeTrackAndSnapsToTheStep() async {
        let model = LyricsModel(source: StubCatalog(best: match()), defaults: scratchDefaults())
        await model.load(signature())
        model.sync(time: 9.9, isPlaying: false)
        #expect(model.activeIndex == 0)

        model.nudge(by: -LyricsModel.offsetStep)

        #expect(model.offset == -LyricsModel.offsetStep)
        #expect(model.activeIndex == 1)
    }

    @Test func theNudgeStopsAtItsLimit() {
        let model = LyricsModel(source: StubCatalog(), defaults: scratchDefaults())

        for _ in 0..<200 {
            model.nudge(by: LyricsModel.offsetStep)
        }

        #expect(model.offset == LyricsModel.widestOffset)
    }

    @Test func theTypeSizeIsRemembered() {
        let defaults = scratchDefaults()
        let model = LyricsModel(source: StubCatalog(), defaults: defaults)
        #expect(model.textSize == .huge)

        model.textSize = .regular

        let reopened = LyricsModel(source: StubCatalog(), defaults: defaults)
        #expect(reopened.textSize == .regular)
    }

    @Test func aFreshTrackStartsBackInSync() async {
        let model = LyricsModel(source: StubCatalog(best: match()), defaults: scratchDefaults())
        await model.load(signature())
        model.nudge(by: 2)
        #expect(model.offset == 2)

        await model.load(signature(title: "Something Else"))

        #expect(model.offset == 0)
    }

    @Test func theTimingCanBePutBack() {
        let model = LyricsModel(source: StubCatalog(), defaults: scratchDefaults())
        model.nudge(by: 2)

        model.resetOffset()

        #expect(model.offset == 0)
    }

    // MARK: - Choosing another match

    @Test func anotherMatchReplacesTheWords() async {
        let other = match(id: 9, synced: "[00:05.00] different")
        let model = LyricsModel(source: StubCatalog(best: match(), others: [other]), defaults: scratchDefaults())
        await model.load(signature())

        await model.findAlternatives()
        #expect(model.alternatives.map(\.id) == [9])

        model.use(other)

        #expect(model.matched?.id == 9)
        #expect(model.lines.map(\.text) == ["", "different"])
    }

    @Test func aFreshTrackDropsTheEarlierOne() async {
        let model = LyricsModel(source: StubCatalog(best: match()), defaults: scratchDefaults())
        await model.load(signature())
        #expect(model.isSynced)

        await model.load(signature(isPrivate: true))

        #expect(model.matched == nil)
        #expect(model.lines.isEmpty)
        #expect(model.alternatives.isEmpty)
    }

    // MARK: - The setting

    @Test func lyricsStayOffUntilTheyAreAdded() {
        let defaults = scratchDefaults()

        #expect(!BrowserSettings(defaults: defaults).showsLyrics)

        BrowserSettings(defaults: defaults).showsLyrics = true

        #expect(BrowserSettings(defaults: defaults).showsLyrics)
    }
}
