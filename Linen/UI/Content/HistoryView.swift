// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct HistoryView: View {
    let browser: BrowserModel

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        DestinationPage {
            toolbar
        } content: {
            LazyVStack(alignment: .leading, spacing: 2) {
                if days.isEmpty {
                    emptyLine
                        .font(Theme.Font.row)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.top, 28)
                } else {
                    ForEach(days) { day in
                        Section {
                            ForEach(day.rows) { row in
                                HistoryRow(
                                    entry: row.entry,
                                    action: { open(row.entry.url) },
                                    onRemove: { remove(row) }
                                )
                            }
                        } header: {
                            dayHeader(day)
                        }
                    }
                }
            }
        }
    }

    /// Two statements, not one ternary. A choice between two literals in an
    /// argument extracts only its first branch into the catalog.
    @ViewBuilder
    private var emptyLine: some View {
        if query.isEmpty {
            Text("No pages visited yet.")
        } else {
            Text("No pages match “\(query)”.")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            DestinationTitle(title: "History") {
                browser.dismissInternalPage(.history)
            }

            DestinationCount(count: browser.history.count)

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(Theme.Font.label)
                    .foregroundStyle(.tertiary)
                TextField("", text: $query)
                    .fieldPlaceholder("Search history", isShowing: query.isEmpty)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.row)
                    .focused($searchFocused)
                if !query.isEmpty {
                    ChromeIcon(
                        symbol: "xmark",
                        size: 9,
                        extent: 18,
                        help: String(localized: "Clear Search")
                    ) {
                        query = ""
                        searchFocused = true
                    }
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .frame(maxWidth: 240)
            .glassSurface(
                in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
            )

            ToolbarChip(symbol: "trash", label: "Clear", isDestructive: true) {
                Task { await clear() }
            }
            .disabled(browser.history.count == 0)
        }
    }

    private func clear() async {
        guard let choice = await ConfirmAlert.clear(.history()) else { return }
        await BrowsingData.clear(choice.kinds, range: choice.range, history: browser.history)
        query = ""
    }

    private func dayHeader(_ day: Day) -> some View {
        Text(verbatim: day.title)
            .font(.system(size: 11.5, weight: .semibold))
            .kerning(0.4)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    struct Row: Identifiable {
        let id: String
        let entry: HistoryStore.Entry
        let visitID: Int64?
    }

    private var matching: [Row] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            return browser.history.visits.map {
                Row(id: "visit-\($0.id)", entry: $0.entry, visitID: $0.id)
            }
        }
        return browser.history.search(matching: HistoryQuery.parse(needle), limit: 500)
            .sorted { $0.date > $1.date }
            .map { Row(id: "page-\($0.url)", entry: $0, visitID: nil) }
    }

    struct Day: Identifiable {
        let id: Date
        let title: String
        let rows: [Row]
    }

    private var days: [Day] {
        let calendar = Calendar.current
        var groups: [Day] = []
        var current: [Row] = []
        var currentDay: Date?

        for row in matching {
            let day = calendar.startOfDay(for: row.entry.date)
            if day != currentDay {
                if let currentDay {
                    groups.append(Day(id: currentDay, title: Self.title(for: currentDay, calendar: calendar), rows: current))
                }
                currentDay = day
                current = []
            }
            current.append(row)
        }
        if let currentDay {
            groups.append(Day(id: currentDay, title: Self.title(for: currentDay, calendar: calendar), rows: current))
        }
        return groups
    }

    private static func title(for day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) {
            return String(localized: "Today")
        }
        if calendar.isDateInYesterday(day) {
            return String(localized: "Yesterday")
        }

        let daysAgo = calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: .now)).day ?? 0
        if daysAgo < 7 {
            return day.formatted(.dateTime.weekday(.wide))
        }
        if calendar.isDate(day, equalTo: .now, toGranularity: .year) {
            return day.formatted(.dateTime.weekday(.abbreviated).day().month(.wide))
        }
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.wide).year())
    }

    private func open(_ url: String) {
        guard let parsed = URL(string: url) else { return }
        browser.ensureActiveTab().load(parsed)
    }

    private func remove(_ row: Row) {
        if let visitID = row.visitID {
            browser.history.removeVisit(visitID)
        } else {
            browser.history.remove(row.entry)
        }
    }
}
