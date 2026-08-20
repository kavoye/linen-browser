// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

struct BrowsingDataTests {
    @Test func kindsMapToDistinctWebsiteDataGroups() {
        let cookies = BrowsingData.Kind.cookies.dataTypes
        let cache = BrowsingData.Kind.cache.dataTypes

        #expect(BrowsingData.Kind.history.dataTypes.isEmpty)
        #expect(cookies.contains(WKWebsiteDataTypeCookies))
        #expect(cookies.contains(WKWebsiteDataTypeIndexedDBDatabases))
        #expect(cache.contains(WKWebsiteDataTypeDiskCache))
        #expect(cache.contains(WKWebsiteDataTypeMemoryCache))
        #expect(cookies.isDisjoint(with: cache))
    }

    @Test func rangeIdentifiersAreStableAndComplete() {
        #expect(BrowsingData.Range.allCases.map(\.id) == [
            "hour", "day", "week", "month", "everything",
        ])
    }

    @Test func finiteRangesUseTheExpectedDuration() {
        let now = Date()
        let expected: [(BrowsingData.Range, TimeInterval)] = [
            (.hour, 3_600),
            (.day, 86_400),
            (.week, 7 * 86_400),
            (.month, 30 * 86_400),
        ]

        for (range, duration) in expected {
            let age = now.timeIntervalSince(range.since)
            #expect(abs(age - duration) < 1)
        }
    }

    @Test func allTimeStartsAtTheUnixEpoch() {
        #expect(BrowsingData.Range.everything.since == Date(timeIntervalSince1970: 0))
    }

    // MARK: - The clear prompt

    @Test func bothClearPromptsOfferEveryRange() {
        #expect(BrowsingData.ClearPrompt.history().ranges == BrowsingData.Range.allCases)
        #expect(BrowsingData.ClearPrompt.privacy().ranges == BrowsingData.Range.allCases)
        #expect(BrowsingData.ClearPrompt.initialRange == .everything)
        #expect(String(localized: BrowsingData.ClearPrompt.verb) == "Clear")
    }

    @Test func theHistoryPromptClearsOnlyHistoryAndDoesNotAskWhat() {
        let prompt = BrowsingData.ClearPrompt.history()
        #expect(prompt.kinds == [.history])
        #expect(!prompt.offersKindChoice)
        #expect(prompt.selectableKinds.isEmpty)
    }

    @Test func thePrivacyPromptAsksWhatToClearWithEverythingTicked() {
        let prompt = BrowsingData.ClearPrompt.privacy()
        #expect(prompt.offersKindChoice)
        #expect(prompt.selectableKinds == BrowsingData.Kind.allCases)
        #expect(prompt.kinds == Set(BrowsingData.Kind.allCases))
    }

    @Test func thePrivacyPromptDoesNotNameTheKindsInItsText() {
        let detail = String(localized: BrowsingData.ClearPrompt.privacy().detail)
        for kind in BrowsingData.Kind.allCases {
            #expect(!detail.lowercased().contains(String(localized: kind.listName)))
        }
    }

    @Test func aChoiceCarriesBothAnswers() {
        let choice = BrowsingData.ClearChoice(kinds: [.history, .cache], range: .week)
        #expect(choice.kinds == [.history, .cache])
        #expect(choice.range == .week)
    }
}
