// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// The History page shows a page once per day however often it was visited:
/// the latest visit fronts the row, and the row stands for every visit of that
/// page on that day.
@MainActor
struct HistoryDayCollapseTests {
    private let calendar = Calendar.current

    private var today: Date {
        calendar.startOfDay(for: .now)
    }

    private func row(
        _ url: String,
        at date: Date,
        visit: Int64,
        title: String = "Page",
        trail: Int64? = nil
    ) -> HistoryView.Row {
        HistoryView.Row(
            id: "visit-\(visit)",
            entry: HistoryStore.Entry(url: url, title: title, date: date),
            visitIDs: [visit],
            trail: trail
        )
    }

    @Test func revisitsWithinADayCollapseIntoTheLatest() {
        let days = HistoryView.days(collapsing: [
            row("https://example.com/a", at: today.addingTimeInterval(7200), visit: 3, title: "Latest"),
            row("https://example.com/b", at: today.addingTimeInterval(5400), visit: 2),
            row("https://example.com/a", at: today.addingTimeInterval(3600), visit: 1, title: "Earlier"),
        ], calendar: calendar)

        #expect(days.count == 1)
        #expect(days.first?.rows.count == 2)
        let collapsed = days.first?.rows.first
        #expect(collapsed?.entry.title == "Latest")
        #expect(collapsed?.visitIDs == [3, 1], "the row stands for both visits")
        #expect(days.first?.rows.last?.visitIDs == [2])
    }

    @Test func theSamePageOnAnotherDayIsItsOwnRow() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let days = HistoryView.days(collapsing: [
            row("https://example.com/a", at: today.addingTimeInterval(3600), visit: 2),
            row("https://example.com/a", at: yesterday.addingTimeInterval(3600), visit: 1),
        ], calendar: calendar)

        #expect(days.count == 2)
        #expect(days.first?.rows.map(\.visitIDs) == [[2]])
        #expect(days.last?.rows.map(\.visitIDs) == [[1]])
    }

    @Test func distinctPagesStaySeparateAndInOrder() {
        let days = HistoryView.days(collapsing: [
            row("https://example.com/a", at: today.addingTimeInterval(7200), visit: 2),
            row("https://example.com/b", at: today.addingTimeInterval(3600), visit: 1),
        ], calendar: calendar)

        #expect(days.first?.rows.map(\.id) == ["visit-2", "visit-1"])
    }

    @Test func nothingMakesNoDays() {
        #expect(HistoryView.days(collapsing: [], calendar: calendar).isEmpty)
    }

    @Test func aTrailGroupsUnderItsFirstPage() {
        let days = HistoryView.days(collapsing: [
            row("https://jira.example/browse/2", at: today.addingTimeInterval(4000), visit: 4, trail: 1),
            row("https://twitch.example/", at: today.addingTimeInterval(3900), visit: 3, trail: 3),
            row("https://jira.example/browse/1", at: today.addingTimeInterval(3800), visit: 2, trail: 1),
            row("https://jira.example/board", at: today.addingTimeInterval(3600), visit: 1, title: "Board", trail: 1),
        ], calendar: calendar)

        let trails = days.first?.trails ?? []
        #expect(trails.map(\.rows.count) == [3, 1])
        #expect(trails.first?.root.entry.title == "Board")
        #expect(trails.first?.pages.map(\.id) == ["visit-4", "visit-2"])
    }

    @Test func aRevisitInsideATrailCollapses() {
        let days = HistoryView.days(collapsing: [
            row("https://jira.example/board", at: today.addingTimeInterval(4000), visit: 3, trail: 1),
            row("https://jira.example/browse/1", at: today.addingTimeInterval(3800), visit: 2, trail: 1),
            row("https://jira.example/board", at: today.addingTimeInterval(3600), visit: 1, trail: 1),
        ], calendar: calendar)

        #expect(days.first?.trails.first?.rows.map(\.visitIDs) == [[3, 1], [2]])
    }

    @Test func theSamePageInTwoTrailsStaysInBoth() {
        let days = HistoryView.days(collapsing: [
            row("https://jira.example/board", at: today.addingTimeInterval(4000), visit: 2, trail: 2),
            row("https://jira.example/board", at: today.addingTimeInterval(3600), visit: 1, trail: 1),
        ], calendar: calendar)

        #expect(days.first?.trails.map(\.rows.count) == [1, 1])
    }
}
