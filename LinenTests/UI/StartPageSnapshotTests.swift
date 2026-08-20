// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@MainActor
struct StartPageSnapshotTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    @Test func repeatedVisitsToOnePageCanEarnAFrequentSite() {
        let visits = [
            visit(id: 3, url: "https://docs.example/guide", day: 3),
            visit(id: 2, url: "https://docs.example/guide", day: 2),
            visit(id: 1, url: "https://docs.example/guide", day: 2),
        ]

        let sites = StartPageSnapshot.frequentSites(
            from: visits,
            hiddenHosts: [],
            calendar: calendar
        )

        #expect(sites == [
            StartPageSite(
                url: "https://docs.example/guide",
                host: "docs.example",
                visits: 3
            ),
        ])
    }

    @Test func frequentSitesExcludeSearchAndDismissedHostsThenRankDeterministically() {
        let visits = [
            visit(id: 20, url: "https://beta.example/latest", day: 5),
            visit(id: 19, url: "https://alpha.example/latest", day: 5),
            visit(id: 18, url: "https://hidden.example/latest", day: 5),
            visit(id: 17, url: "https://duckduckgo.com/?q=browser", day: 5),
            visit(id: 16, url: "https://beta.example/older", day: 4),
            visit(id: 15, url: "https://beta.example/oldest", day: 3),
            visit(id: 14, url: "https://beta.example/fourth", day: 2),
            visit(id: 13, url: "https://alpha.example/older", day: 4),
            visit(id: 12, url: "https://alpha.example/oldest", day: 3),
            visit(id: 11, url: "https://hidden.example/older", day: 4),
            visit(id: 10, url: "https://hidden.example/oldest", day: 3),
            visit(id: 9, url: "https://duckduckgo.com/?q=swift", day: 4),
            visit(id: 8, url: "https://duckduckgo.com/?q=webkit", day: 3),
        ]

        let sites = StartPageSnapshot.frequentSites(
            from: visits,
            hiddenHosts: ["hidden.example"],
            calendar: calendar
        )

        #expect(sites.map(\.host) == ["beta.example", "alpha.example"])
        #expect(sites.map(\.visits) == [4, 3])
        #expect(sites.first?.url == "https://beta.example/latest")
    }

    @Test func snapshotBoundsEverySectionAndKeepsNewestTasksFirst() {
        let history = (0..<8).map { index in
            HistoryStore.Entry(
                url: "https://history-\(index).example/",
                title: "History \(index)",
                lastVisit: Date(timeIntervalSinceReferenceDate: Double(100 - index))
            )
        }
        let downloads = (0..<5).map { index in
            DownloadManager.Item(
                id: UUID(),
                filename: "File \(index)",
                source: "downloads.example",
                sourceTabID: nil
            )
        }
        let tasks = (0..<4).map { index in
            ConversationLog.TaskTrace(
                id: UUID(),
                tabID: UUID(),
                prompt: "Task \(index)",
                startedAt: Date(timeIntervalSinceReferenceDate: Double(index)),
                steps: [],
                response: "",
                state: .completed,
                finishedAt: Date(timeIntervalSinceReferenceDate: Double(index + 1))
            )
        }

        let snapshot = StartPageSnapshot(
            historyEntries: history,
            historyVisits: [],
            downloads: downloads,
            tasks: tasks,
            hiddenFrequentHosts: [],
            calendar: calendar
        )

        #expect(snapshot.recentHistory.count == 6)
        #expect(snapshot.recentDownloads.count == 4)
        #expect(snapshot.recentTasks.map(\.prompt) == ["Task 3", "Task 2", "Task 1"])
        #expect(snapshot.visibleSections(in: StartPageSection.allCases) { _ in true }.map(\.id)
            == [.recentTasks, .history, .downloads])
    }

    @Test func startPagePreferencesAreIsolatedBindableAndPersistent() {
        let suiteName = "StartPageSnapshotTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = BrowserSettings(defaults: defaults)
        settings[showsStartPageSection: .history] = false
        settings.moveStartPageSections(from: IndexSet(integer: 0), to: 4)
        settings.hideFrequentSite(host: "Example.COM")

        #expect(!settings.showsStartPageSection(.history))
        #expect(settings.startPageOrder == [.frequentSites, .history, .downloads, .recentTasks])
        #expect(settings.hiddenFrequentHosts == ["example.com"])

        let restored = BrowserSettings(defaults: defaults)
        #expect(!restored[showsStartPageSection: .history])
        #expect(restored.startPageOrder == settings.startPageOrder)
        #expect(restored.hiddenFrequentHosts == ["example.com"])

        restored.restoreHiddenFrequentSites()
        #expect(restored.hiddenFrequentHosts.isEmpty)
    }

    private func visit(
        id: Int64,
        url: String,
        day: Int
    ) -> HistoryStore.VisitedPage {
        HistoryStore.VisitedPage(
            id: id,
            url: url,
            title: url,
            visitedAt: calendar.date(from: DateComponents(year: 2026, month: 8, day: day))!,
            transition: .link
        )
    }
}
