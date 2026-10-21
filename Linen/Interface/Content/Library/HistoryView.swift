// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct HistoryView: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator

    @State private var query = ""
    @State private var hover = HistoryHover()
    @State private var collapsedTrails: Set<String> = []

    var body: some View {
        DestinationPage {
            toolbar
        } content: {
            let days = days
            LazyVStack(alignment: .leading, spacing: 0) {
                if days.isEmpty {
                    emptyLine
                        .font(Theme.Font.row)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.top, 28)
                } else {
                    ForEach(days) { day in
                        Section {
                            ForEach(lines(of: day)) { line in
                                row(line)
                            }
                        } header: {
                            dayHeader(day)
                        }
                    }
                    if query.isEmpty, browser.history.hasOlderVisits {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .onAppear { browser.history.loadOlderVisits() }
                    }
                }
            }
            .onMiddleClick {
                guard let url = hover.url else { return }
                openInNewTab(url, activate: false)
            }
        }
        .overlay(alignment: .bottomLeading) {
            HistoryLinkPreview(hover: hover)
        }
        .onChange(of: query) { hover.url = nil }
    }

    struct Line: Identifiable {
        let row: Row
        let indent: CGFloat
        var disclosure: Trail?
        var isNested = false
        var showsHost = true

        var id: String {
            row.id
        }
    }

    private func lines(of day: Day) -> [Line] {
        var lines: [Line] = []
        for trail in day.trails {
            let root = trail.root
            lines.append(Line(
                row: root,
                indent: 0,
                disclosure: trail.pages.isEmpty ? nil : trail
            ))
            guard !trail.pages.isEmpty, !collapsedTrails.contains(trail.id) else { continue }
            let site = URL(string: root.entry.url)?.displayHost
            for page in trail.pages {
                lines.append(Line(
                    row: page,
                    indent: HistoryRow.nestedIndent,
                    isNested: true,
                    showsHost: URL(string: page.entry.url)?.displayHost != site
                ))
            }
        }
        return lines
    }

    private func row(_ line: Line) -> some View {
        let row = line.row
        return HistoryRow(
            entry: row.entry,
            action: { open(row.entry.url) },
            onRemove: { remove(row) },
            onOpenInNewTab: { openInNewTab(row.entry.url, activate: $0) },
            onOpenInNewWindow: { isPrivate in
                guard let url = URL(string: row.entry.url) else { return }
                coordinator.openLinkInNewWindow(url, isPrivate: isPrivate)
            },
            isPrivate: browser.opensPrivately,
            onHoverChanged: { noteHover(of: row.entry.url, $0) },
            indent: line.indent,
            disclosure: line.disclosure.map { trail in
                HistoryRow.Disclosure(
                    count: trail.rows.count,
                    isExpanded: !collapsedTrails.contains(trail.id),
                    toggle: { toggle(trail) }
                )
            },
            showsHost: line.showsHost,
            showsGuide: line.isNested
        )
        .equatable()
        .padding(.top, line.isNested ? 0 : 2)
    }

    private func toggle(_ trail: Trail) {
        if collapsedTrails.contains(trail.id) {
            collapsedTrails.remove(trail.id)
        } else {
            collapsedTrails.insert(trail.id)
        }
    }

    private func noteHover(of url: String, _ inside: Bool) {
        if inside {
            hover.url = url
        } else if hover.url == url {
            hover.url = nil
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

            ToolbarSearchField(query: $query, placeholder: "Search history")

            ToolbarChip(symbol: "trash", label: "Clear", isDestructive: true) {
                Task { await clear() }
            }
            .disabled(browser.history.count == 0)
        }
    }

    private func clear() async {
        guard let choice = await ConfirmAlert.clear(.history()) else { return }
        await BrowsingData.clear(choice.kinds, range: choice.range, history: browser.history, context: browser.context)
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
        var visitIDs: [Int64]
        var trail: Int64?
    }

    struct Trail: Identifiable {
        let id: String
        var rows: [Row]

        var root: Row {
            rows.min { ($0.visitIDs.min() ?? .max) < ($1.visitIDs.min() ?? .max) } ?? rows[0]
        }
        var pages: [Row] {
            let root = root.id
            return rows.filter { $0.id != root }
        }
    }

    private var matching: [Row] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            return browser.history.visits.map {
                Row(id: "visit-\($0.id)", entry: $0.entry, visitIDs: [$0.id], trail: $0.trail)
            }
        }
        return browser.history.search(matching: HistoryQuery.parse(needle), limit: 500)
            .sorted { $0.date > $1.date }
            .map { Row(id: "page-\($0.url)", entry: $0, visitIDs: []) }
    }

    struct Day: Identifiable {
        let id: Date
        let title: String
        let trails: [Trail]

        var rows: [Row] {
            trails.flatMap(\.rows)
        }
    }

    private var days: [Day] {
        Self.days(collapsing: matching, calendar: .current)
    }

    static func days(collapsing rows: [Row], calendar: Calendar) -> [Day] {
        var groups: [Day] = []
        var current: [Trail] = []
        var indexByGroup: [String: Int] = [:]
        var indexByPage: [String: Int] = [:]
        var currentDay: Date?

        func closeDay() {
            guard let currentDay else { return }
            groups.append(Day(
                id: currentDay,
                title: title(for: currentDay, calendar: calendar),
                trails: current
            ))
        }

        for row in rows {
            let day = calendar.startOfDay(for: row.entry.date)
            if day != currentDay {
                closeDay()
                currentDay = day
                current = []
                indexByGroup = [:]
                indexByPage = [:]
            }
            let group = row.trail.map { "trail-\($0)" } ?? "page-\(row.entry.url)"
            let page = "\(group) \(row.entry.url)"
            if let trail = indexByGroup[group] {
                if let index = indexByPage[page] {
                    current[trail].rows[index].visitIDs.append(contentsOf: row.visitIDs)
                } else {
                    indexByPage[page] = current[trail].rows.count
                    current[trail].rows.append(row)
                }
            } else {
                indexByGroup[group] = current.count
                indexByPage[page] = 0
                current.append(Trail(id: "\(group) \(day.timeIntervalSinceReferenceDate)", rows: [row]))
            }
        }
        closeDay()
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

    private func openInNewTab(_ url: String, activate: Bool) {
        guard let parsed = URL(string: url) else { return }
        browser.newTab(url: parsed, activate: activate, after: browser.activeTab)
    }

    private func remove(_ row: Row) {
        if row.visitIDs.isEmpty {
            browser.history.remove(row.entry)
        } else {
            browser.history.removeVisits(row.visitIDs)
        }
        if hover.url == row.entry.url {
            hover.url = nil
        }
    }
}

@Observable
final class HistoryHover {
    var url: String?
}

private struct HistoryLinkPreview: View {
    let hover: HistoryHover

    var body: some View {
        LinkPreview(address: hover.url, delay: .zero, obeysSetting: false)
    }
}
