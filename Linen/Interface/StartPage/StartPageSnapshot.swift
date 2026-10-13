// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct StartPageSite: Identifiable, Equatable {
    let url: String
    let host: String
    let visits: Int

    var domain: String {
        SiteName.domain(forHost: host)
    }

    var id: String {
        domain
    }
    var title: String {
        SiteName.title(forHost: host)
    }
}

enum StartPageSectionSnapshot: Identifiable, Equatable {
    case suggestions
    case recentTasks([ConversationLog.TaskTrace])
    case frequentSites([StartPageSite])
    case history([HistoryStore.Entry])
    case downloads([DownloadManager.Item])

    var id: StartPageSection {
        switch self {
        case .suggestions:
            .suggestions
        case .recentTasks:
            .recentTasks
        case .frequentSites:
            .frequentSites
        case .history:
            .history
        case .downloads:
            .downloads
        }
    }
}

struct StartPageSnapshot {
    let frequentSites: [StartPageSite]
    let recentHistory: [HistoryStore.Entry]
    let recentDownloads: [DownloadManager.Item]
    let recentTasks: [ConversationLog.TaskTrace]

    init(
        historyEntries: [HistoryStore.Entry],
        historyVisits: [HistoryStore.VisitedPage],
        downloads: [DownloadManager.Item],
        tasks: [ConversationLog.TaskTrace],
        hiddenFrequentHosts: Set<String>,
        calendar: Calendar = .current
    ) {
        frequentSites = Self.frequentSites(
            from: historyVisits,
            hiddenHosts: hiddenFrequentHosts,
            calendar: calendar
        )
        recentHistory = Array(historyEntries.prefix(6))
        recentDownloads = Array(downloads.prefix(4))
        recentTasks = Array(tasks.suffix(3).reversed())
    }

    private func sectionSnapshot(_ section: StartPageSection) -> StartPageSectionSnapshot? {
        switch section {
        case .suggestions:
            .suggestions
        case .recentTasks:
            recentTasks.isEmpty ? nil : .recentTasks(recentTasks)
        case .frequentSites:
            frequentSites.isEmpty ? nil : .frequentSites(frequentSites)
        case .history:
            recentHistory.isEmpty ? nil : .history(recentHistory)
        case .downloads:
            recentDownloads.isEmpty ? nil : .downloads(recentDownloads)
        }
    }

    func visibleSections(
        in order: [StartPageSection],
        isShown: (StartPageSection) -> Bool
    ) -> [StartPageSectionSnapshot] {
        order.compactMap { section in
            guard isShown(section) else { return nil }
            return sectionSnapshot(section)
        }
    }

    private struct SiteTally {
        var visits: Int
        var days: Set<Date>
        var latestURL: String
        var hosts: [String: Int]

        mutating func record(_ visit: HistoryStore.VisitedPage, host: String, calendar: Calendar) {
            visits += 1
            if days.count < 2 {
                days.insert(calendar.startOfDay(for: visit.visitedAt))
            }
            hosts[host, default: 0] += 1
        }
    }

    static func frequentSites(
        from visits: [HistoryStore.VisitedPage],
        hiddenHosts: Set<String>,
        calendar: Calendar = .current
    ) -> [StartPageSite] {
        var statistics: [String: SiteTally] = [:]
        var domains: [String: String] = [:]
        var excludedHosts = hiddenHosts

        for visit in visits.prefix(400) {
            guard let parsedHost = URL(string: visit.url)?.host() else { continue }
            let host = parsedHost.lowercased()
            guard !excludedHosts.contains(host) else { continue }
            let domain: String
            if let cached = domains[host] {
                domain = cached
            } else {
                domain = SiteName.domain(forHost: host)
                guard !hiddenHosts.contains(domain), !SearchEngineHosts.isSearchEngine(host) else {
                    excludedHosts.insert(host)
                    continue
                }
                domains[host] = domain
            }

            statistics[domain, default: SiteTally(visits: 0, days: [], latestURL: visit.url, hosts: [:])]
                .record(visit, host: host, calendar: calendar)
        }

        return statistics.compactMap { domain, statistic in
            guard statistic.visits >= 3, statistic.days.count >= 2 else { return nil }
            let host = statistic.hosts
                .max { first, second in
                    first.value == second.value ? first.key > second.key : first.value < second.value
                }?
                .key
            return StartPageSite(
                url: statistic.latestURL,
                host: host ?? domain,
                visits: statistic.visits
            )
        }
        .sorted { first, second in
            first.visits == second.visits
                ? first.domain < second.domain
                : first.visits > second.visits
        }
        .prefix(10)
        .map { $0 }
    }
}
