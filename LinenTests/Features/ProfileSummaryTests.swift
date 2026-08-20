// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

struct ProfileSummaryTests {
    private static let dot = " · "

    @Test func anEmptyProfileNeverCountsToZero() {
        #expect(!ProfileSummary.tabs(0).contains("0"))
        #expect(!ProfileSummary.extensions(0).contains("0"))
        #expect(!ProfileSummary.permissions(0).contains("0"))
        #expect(!ProfileSummary.history(pages: 0, since: nil).contains("0"))
        #expect(!ProfileSummary.size(0).contains("0"))
    }

    @Test func aNegativeSizeReadsAsEmptyRatherThanAsBytes() {
        #expect(ProfileSummary.size(-1) == ProfileSummary.size(0))
    }

    @Test func countsCarryTheirNumber() {
        #expect(ProfileSummary.tabs(7).contains("7"))
        #expect(ProfileSummary.extensions(3).contains("3"))
        #expect(ProfileSummary.permissions(12).contains("12"))
        #expect(ProfileSummary.history(pages: 40, since: nil).contains("40"))
    }

    @Test func aSizeIsSpelledInFileUnits() {
        let text = ProfileSummary.size(2_000_000)
        #expect(text.contains("2"))
        #expect(text.uppercased().contains("MB"))
    }

    // MARK: - Joining

    @Test func noFoldersMeansTheTabLineAlone() {
        #expect(ProfileSummary.tabsAndFolders(tabs: 5, folders: 0) == ProfileSummary.tabs(5))
        #expect(!ProfileSummary.tabsAndFolders(tabs: 5, folders: 0).contains(Self.dot))
    }

    @Test func foldersJoinOntoTheTabLineWithoutLosingEitherHalf() {
        let line = ProfileSummary.tabsAndFolders(tabs: 5, folders: 2)
        #expect(line.contains(Self.dot))
        #expect(line.hasPrefix(ProfileSummary.tabs(5)))
        #expect(line.contains("2"))
    }

    @Test func foldersOnAnEmptyProfileStillReadAsASentence() {
        let line = ProfileSummary.tabsAndFolders(tabs: 0, folders: 3)
        #expect(line.hasPrefix(ProfileSummary.tabs(0)))
        #expect(line.contains("3"))
    }

    @Test func historyWithoutADateHasNoTrailingSeparator() {
        let line = ProfileSummary.history(pages: 9, since: nil)
        #expect(!line.contains(Self.dot))
    }

    @Test func historyWithADateNamesTheMonthItStartedFrom() {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 14
        let start = Calendar(identifier: .gregorian).date(from: components)!

        let line = ProfileSummary.history(pages: 9, since: start)
        #expect(line.contains(Self.dot))
        #expect(line.contains(start.formatted(.dateTime.month(.wide).day())))
    }

    @Test func anEmptyHistoryIgnoresTheDateEntirely() {
        let line = ProfileSummary.history(pages: 0, since: .now)
        #expect(line == ProfileSummary.history(pages: 0, since: nil))
        #expect(!line.contains(Self.dot))
    }

    // MARK: - The separation list

    @Test func everyLineAProfileSeparatesIsNamedOnce() {
        let keys = ProfileSummary.separated.map(\.key)
        #expect(keys.count == Set(keys).count)
        #expect(!keys.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty })
    }
}
