// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import Testing

@testable import Linen

struct LyricsMetricsTests {
    @Test func theTypeGrowsWithTheWindowButStaysReadable() {
        #expect(LyricsMetrics.fontSize(forWidth: 300) == 20)
        #expect(LyricsMetrics.fontSize(forWidth: 800) == 34)
        #expect(LyricsMetrics.fontSize(forWidth: 2400) == 38)
    }

    @Test func theColumnStopsWideningOnALargeDisplay() {
        #expect(LyricsMetrics.columnWidth(forWidth: 600) == 528)
        #expect(LyricsMetrics.columnWidth(forWidth: 2400) == LyricsMetrics.widestColumn)
        #expect(LyricsMetrics.columnWidth(forWidth: 120) == 160)
    }

    @Test func theTypeSizeScalesTheWholeRange() {
        #expect(LyricsTextSize.regular.scale == 1)
        #expect(LyricsMetrics.fontSize(forWidth: 800) == 34)
        #expect(LyricsMetrics.fontSize(forWidth: 800, scale: LyricsTextSize.huge.scale) == 49)
        #expect(LyricsMetrics.fontSize(forWidth: 800, scale: LyricsTextSize.small.scale) == 29)
    }

    @Test func everyTypeSizeIsDistinctAndOrdered() {
        let scales = LyricsTextSize.allCases.map(\.scale)
        #expect(scales == scales.sorted())
        #expect(Set(scales).count == scales.count)
    }

    @Test func theColumnGutterShrinksWithThePanel() {
        let panel = SidePanelMetrics.defaultWidth
        #expect(LyricsMetrics.columnWidth(forWidth: panel) > panel * 0.8)
        #expect(LyricsMetrics.columnWidth(forWidth: panel) < panel)
    }

    @Test func linesFadeWithDistanceFromTheOneBeingSung() {
        #expect(LyricsMetrics.fade(atDistance: 0) == 1)
        #expect(LyricsMetrics.fade(atDistance: -1) == LyricsMetrics.fade(atDistance: 1))
        #expect(LyricsMetrics.fade(atDistance: 1) > LyricsMetrics.fade(atDistance: 4))
        #expect(LyricsMetrics.fade(atDistance: 1) < 0.5)
    }

    @Test func aWordLightsUpAcrossItsOwnWindow() {
        let word = LyricsWord(text: "one", start: 10, end: 11)

        #expect(LyricsMetrics.sungShare(of: word, at: 9) == 0)
        #expect(LyricsMetrics.sungShare(of: word, at: 12) == 1)
        #expect(abs(LyricsMetrics.sungShare(of: word, at: 10.5) - 0.5) < 0.000_001)
    }

    @Test func anUnsungWordIsStillLegible() {
        #expect(LyricsMetrics.wordOpacity(0) == LyricsMetrics.dimmestWord)
        #expect(LyricsMetrics.wordOpacity(1) == 1)
        #expect(LyricsMetrics.dimmestWord > LyricsMetrics.fade(atDistance: 1))
    }

    @Test func aWordOfNoLengthIsAlreadySung() {
        let word = LyricsWord(text: "one", start: 10, end: 10)

        #expect(LyricsMetrics.sungShare(of: word, at: 10) == 1)
    }

    @Test func theDotsFillOneAfterAnotherAcrossTheGap() {
        #expect(LyricsMetrics.dotFill(0, progress: 0) == 0)
        #expect(LyricsMetrics.dotFill(0, progress: 0.34) == 1)
        #expect(LyricsMetrics.dotFill(1, progress: 0.34) > 0)
        #expect(LyricsMetrics.dotFill(2, progress: 0.34) == 0)
        #expect(LyricsMetrics.dotFill(2, progress: 1) == 1)
    }

    @Test func gapProgressIsClampedToTheGap() {
        let line = LyricsLine(id: 0, start: 10, end: 20, text: "", words: [])

        #expect(LyricsMetrics.gapProgress(line, at: 5) == 0)
        #expect(LyricsMetrics.gapProgress(line, at: 15) == 0.5)
        #expect(LyricsMetrics.gapProgress(line, at: 25) == 1)
    }
}
