// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

struct LyricsParsingTests {
    private static let sample = """
    [ar:Daft Punk]
    [00:00.00]
    [01:17.45] It might not be the right time
    [01:22.10] I might not be the right one
    [01:25.82] But there's something about us I want to say
    [02:40.00]
    """

    @Test func timestampsBecomeLinesWithEndsFromTheNextLine() {
        let lines = LyricsParser.lines(fromLRC: Self.sample, duration: 233)

        #expect(lines.count == 5)
        #expect(lines[0].isGap)
        #expect(abs(lines[1].start - 77.45) < 0.001)
        #expect(abs(lines[1].end - 82.10) < 0.001)
        #expect(lines[2].text == "I might not be the right one")
        #expect(abs(lines[4].start - 160) < 0.001)
        #expect(abs(lines[4].end - 233) < 0.001)
    }

    @Test func anOffsetTagShiftsEveryLine() {
        let shifted = LyricsParser.lines(
            fromLRC: "[offset:+500]\n[00:02.00] one\n[00:04.00] two",
            duration: 30
        )

        #expect(abs(shifted[0].start - 1.5) < 0.001)
        #expect(abs(shifted[1].start - 3.5) < 0.001)
    }

    @Test func shortSilencesDoNotBecomeGapMarkers() {
        let lines = LyricsParser.lines(
            fromLRC: "[00:00.00] one\n[00:04.00]\n[00:05.00] two",
            duration: 20
        )

        #expect(lines.count == 2)
        #expect(lines[0].text == "one")
        #expect(abs(lines[0].end - 5) < 0.001)
    }

    @Test func aLongIntroGetsItsOwnGapMarker() {
        let lines = LyricsParser.lines(fromLRC: "[00:12.00] first words", duration: 60)

        #expect(lines.count == 2)
        #expect(lines[0].isGap)
        #expect(lines[0].start == 0)
        #expect(abs(lines[0].end - 12) < 0.001)
    }

    @Test func aMusicalNoteCountsAsSilence() {
        let lines = LyricsParser.lines(fromLRC: "[00:00.00] ♪\n[00:09.00] words", duration: 30)

        #expect(lines[0].isGap)
    }

    @Test func plainTextWithoutTimestampsParsesToNothing() {
        #expect(LyricsParser.lines(fromLRC: "just some words\nand more", duration: 30).isEmpty)
    }

    @Test func linesOutOfOrderAreSorted() {
        let lines = LyricsParser.lines(fromLRC: "[00:04.00] two\n[00:02.00] one", duration: 30)

        #expect(lines.map(\.text) == ["one", "two"])
    }

    // MARK: - Word timing

    @Test func wordsShareTheLineAndKeepItsOrder() {
        let words = LyricsParser.words(in: "one two three", from: 10, before: 14)

        #expect(words.map(\.text) == ["one", "two", "three"])
        #expect(words[0].start == 10)
        for pair in zip(words, words.dropFirst()) {
            #expect(abs(pair.0.end - pair.1.start) < 0.000_001)
        }
    }

    @Test func aLongerWordHoldsTheHighlightLonger() {
        let words = LyricsParser.words(in: "a everlasting", from: 0, before: 4)

        #expect(words[1].end - words[1].start > words[0].end - words[0].start)
    }

    @Test func wordsStopSweepingWellBeforeALongInstrumentalTail() {
        let words = LyricsParser.words(in: "two words", from: 0, before: 40)

        #expect(words.last!.end < 4)
    }

    @Test func wordsNeverRunPastAVeryShortLine() {
        let words = LyricsParser.words(in: "a whole lot of words here", from: 0, before: 0.4)

        #expect(words.last!.end <= 0.4001)
    }

    // MARK: - Finding the line

    @Test func theActiveLineIsTheLastOneAlreadyStarted() {
        let lines = LyricsParser.lines(fromLRC: Self.sample, duration: 233)

        #expect(LyricsParser.index(at: 0, in: lines) == 0)
        #expect(LyricsParser.index(at: 77.44, in: lines) == 0)
        #expect(LyricsParser.index(at: 77.46, in: lines) == 1)
        #expect(LyricsParser.index(at: 232, in: lines) == 4)
    }

    @Test func nothingIsActiveBeforeTheFirstLine() {
        let lines = LyricsParser.lines(fromLRC: "[00:10.00] one", duration: 60)

        #expect(LyricsParser.index(at: 0, in: lines) == 0)
        #expect(LyricsParser.index(at: -1, in: lines) == nil)
        #expect(LyricsParser.index(at: 5, in: []) == nil)
    }
}
