// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest

@testable import Linen

// XCTest owns and runs one instance serially. Sendable lets its synchronous
// measurement callback enter the app target's main-actor boundary.
nonisolated final class BrowserPerformanceTests: XCTestCase, @unchecked Sendable {
    func testCreatingAUsableBlankTab() {
        MainActor.assumeIsolated {
            let previousNewTab = BrowserSettings.shared.newTab
            BrowserSettings.shared.newTab = .blank
            defer { BrowserSettings.shared.newTab = previousNewTab }

            measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
                let browser = BrowserModel(database: .temporary())
                let tab = browser.newTab()

                XCTAssertTrue(tab.hasNoPageYet)
                XCTAssertTrue(browser.activeTab === tab)
                browser.cancelPendingSave()
            }
        }
    }

    func testSwitchingTabsInACrowdedSession() {
        MainActor.assumeIsolated {
            let previousNewTab = BrowserSettings.shared.newTab
            BrowserSettings.shared.newTab = .blank
            defer { BrowserSettings.shared.newTab = previousNewTab }

            let browser = BrowserModel(database: .temporary())
            let first = browser.newTab()
            let second = browser.newTab()
            let entries = (0..<100).map { index in
                HistoryStore.Entry(
                    url: "https://fixture-\(index).example/",
                    title: "Fixture \(index)",
                    lastVisit: Date(timeIntervalSinceReferenceDate: Double(index))
                )
            }
            _ = browser.importBookmarksFolder(named: "Performance fixtures", entries: entries)

            measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
                for _ in 0..<250 {
                    browser.activate(first)
                    browser.activate(second)
                }
            }
            browser.cancelPendingSave()
        }
    }

    func testCommandPaletteHistoryRanking() {
        MainActor.assumeIsolated {
            let database = AppDatabase.temporary()
            let history = HistoryStore(database: database, windowSize: 1_000)
            for index in 0..<500 {
                _ = history.record(
                    url: "https://docs.example/project/\(index)",
                    title: "Project documentation \(index)",
                    transition: .link,
                    fromVisit: nil
                )
            }

            measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
                _ = Omnibox.historySection(
                    query: "project 42",
                    store: history,
                    limit: 5,
                    open: { _ in }
                )
            }
        }
    }

    func testCommandPaletteResultProjection() {
        MainActor.assumeIsolated {
            Omnibox.$agentOnlyForTesting.withValue(false) {
                let history = HistoryStore(database: .temporary(), windowSize: 1_000)
                for index in 0..<500 {
                    _ = history.record(
                        url: "https://docs.example/project/\(index)",
                        title: "Project documentation \(index)",
                        transition: .link,
                        fromVisit: nil
                    )
                }
                let tabs = (0..<100).map { index in
                    let tab = BrowserTab()
                    tab.title = "Project tab \(index)"
                    tab.urlString = "https://tabs.example/project/\(index)"
                    return tab
                }
                let actions = CommandPaletteActions()
                var projected: [OmniboxSection] = []

                measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
                    projected = CommandPaletteProjection.sections(
                        query: "project",
                        agentName: "Assistant",
                        history: history,
                        tabs: tabs,
                        phrases: (0..<10).map { "project suggestion \($0)" },
                        actions: actions
                    )
                }

                XCTAssertEqual(projected.map(\.id), ["top", "ask", "tabs", "history", "suggestions"])
                XCTAssertEqual(projected.flattened.count, CommandPaletteBudget.typing)
            }
        }
    }

    func testStartPageFrequentSiteProjection() {
        MainActor.assumeIsolated {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let visits = (0..<400).map { index in
                HistoryStore.VisitedPage(
                    id: Int64(400 - index),
                    url: "https://site-\(index % 20).example/page/\(index)",
                    title: "Fixture \(index)",
                    visitedAt: calendar.date(
                        from: DateComponents(
                            year: 2026,
                            month: 7,
                            day: (index % 28) + 1
                        )
                    )!,
                    transition: .link
                )
            }

            measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
                let sites = StartPageSnapshot.frequentSites(
                    from: visits,
                    hiddenHosts: [],
                    calendar: calendar
                )
                XCTAssertEqual(sites.count, 10)
                XCTAssertEqual(sites.first?.visits, 20)
            }
        }
    }

    func testAskSurfaceResultProjection() {
        MainActor.assumeIsolated {
            Omnibox.$agentOnlyForTesting.withValue(false) {
                let history = HistoryStore(database: .temporary(), windowSize: 1_000)
                for index in 0..<500 {
                    _ = history.record(
                        url: "https://docs.example/project/\(index)",
                        title: "Project documentation \(index)",
                        transition: .link,
                        fromVisit: nil
                    )
                }
                let tab = BrowserTab()
                tab.title = "Project documentation"
                tab.urlString = "https://docs.example/project/open"
                let phrases = (0..<12).map { "project documentation \($0)" }
                var projected: [OmniboxSection] = []

                measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
                    projected = AskSurfaceResults.sections(
                        placement: .startPage,
                        query: "project 42",
                        isFocused: true,
                        isListening: false,
                        currentURL: "",
                        agentOnly: false,
                        agentName: "Assistant",
                        history: history,
                        tabs: [tab],
                        phrases: phrases,
                        open: { _ in },
                        switchTo: { _ in },
                        ask: { _ in }
                    )
                }

                XCTAssertEqual(projected.map(\.id), ["top", "history", "suggestions", "ask"])
                XCTAssertLessThanOrEqual(projected.flattened.count, 10)
            }
        }
    }
}
