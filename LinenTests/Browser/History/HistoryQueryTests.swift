// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// The temporal phrases a history search understands, against a pinned
/// clock: Tuesday 18 August 2026, in a Monday-first week.
struct HistoryQueryTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private static let now = calendar.date(
        from: DateComponents(year: 2026, month: 8, day: 18, hour: 10)
    )!

    private func parse(_ text: String) -> HistoryQuery {
        HistoryQuery.parse(text, now: Self.now, calendar: Self.calendar)
    }

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        Self.calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
    }

    @Test func aPlainQueryPassesThroughUntouched() {
        let query = parse("monday.com news")
        #expect(query.terms == "monday.com news")
        #expect(query.dateRange == nil)
    }

    @Test func yesterdayBecomesADayAndLeavesTheTerms() {
        let query = parse("pricing from Yesterday")
        #expect(query.terms == "pricing")
        #expect(query.dateRange == day(2026, 8, 17)..<day(2026, 8, 18))
    }

    @Test func todayAloneSearchesWithNoTerms() {
        let query = parse("today")
        #expect(query.terms.isEmpty)
        #expect(query.dateRange == day(2026, 8, 18)..<day(2026, 8, 19))
    }

    @Test func lastWeekReachesFromThePreviousWeekToNow() {
        let query = parse("pricing last week")
        #expect(query.terms == "pricing")
        #expect(query.dateRange == day(2026, 8, 10)..<day(2026, 8, 19))
    }

    @Test func countedDaysAndSingleDaysAgoDiffer() {
        #expect(parse("past 2 days").dateRange == day(2026, 8, 17)..<day(2026, 8, 19))
        #expect(parse("docs from 3 days ago").dateRange == day(2026, 8, 15)..<day(2026, 8, 16))
        #expect(parse("docs from 3 days ago").terms == "docs")
    }

    @Test func weekdaysResolveToTheMostRecentOccurrence() {
        #expect(parse("notes on monday").dateRange == day(2026, 8, 17)..<day(2026, 8, 18))
        // Said on a Tuesday, "last tuesday" is a week back, not today.
        #expect(parse("last tuesday").dateRange == day(2026, 8, 11)..<day(2026, 8, 12))
    }

    @Test func monthsResolveWithinThePastYear() {
        #expect(parse("report in june").dateRange == day(2026, 6, 1)..<day(2026, 7, 1))
        // September has not happened yet this year.
        #expect(parse("report in september").dateRange == day(2025, 9, 1)..<day(2025, 10, 1))
    }

    @Test func aBareWeekdayOrMonthStaysASearchTerm() {
        #expect(parse("monday standup notes").dateRange == nil)
        #expect(parse("june retrospective").dateRange == nil)
    }
}
