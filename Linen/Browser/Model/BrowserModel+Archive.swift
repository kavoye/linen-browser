// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

extension BrowserModel {
    // MARK: - Archiving

    func noteUse(of ids: [UUID?], at date: Date = Date()) {
        for id in ids.compactMap({ $0 }) {
            tabsByID[id]?.lastActiveAt = date
            for other in splits.others(of: id) {
                tabsByID[other]?.lastActiveAt = date
            }
        }
    }

    func staleTabs(unusedFor interval: TimeInterval, now: Date = Date()) -> [BrowserTab] {
        let cutoff = now.addingTimeInterval(-interval)
        return tabs.filter { tab in
            tab.id != activeTabID
                && tab.lastActiveAt < cutoff
                && tab.pinnedURL == nil
                && !tab.isPrivate
                && folder(containing: tab) == nil
                && protectionReason(for: tab) == nil
        }
    }

    @discardableResult
    func archiveStaleTabs(now: Date = Date()) -> Int {
        archiveTabs(unusedFor: context.settings.archiveTabsAfter, now: now)
    }

    @discardableResult
    func archiveTabs(unusedFor delay: TabArchiveDelay, now: Date = Date()) -> Int {
        guard !opensPrivately, let interval = delay.interval else { return 0 }
        let stale = staleTabs(unusedFor: interval, now: now)
        guard !stale.isEmpty else { return 0 }
        tabArchive.add(stale.map { ($0.title, $0.urlString) }, at: now)
        for tab in stale {
            close(tab, recordForReopening: false)
        }
        Pipeline.log.notice("archive: archived \(stale.count, privacy: .public) unused tabs")
        return stale.count
    }

    @discardableResult
    func restore(_ entry: TabArchive.Entry) -> BrowserTab? {
        guard let url = URL(string: entry.url) else { return nil }
        tabArchive.remove(entry)
        let tab = newTab(url: url, after: activeTab)
        tab.title = entry.title
        return tab
    }
}
