// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import GRDB
import os
import WebKit

extension BrowserModel {
    // MARK: - Session persistence

    private nonisolated struct TabRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
        static let databaseTableName = "sessionTab"

        var id: UUID
        var title: String
        var url: String
        var state: Data?
        var pinnedURL: URL?
        var pinnedTitle: String?
        var internalPage: BrowserTab.InternalPage?
        var isActive: Bool
    }

    private nonisolated struct FolderRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
        static let databaseTableName = "sessionFolder"

        var id: UUID
        var position: Int
        var name: String
        var color: TabFolderColor
        var isExpanded: Bool
    }

    private nonisolated struct ItemRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
        static let databaseTableName = "sessionItem"

        var position: Int
        var tabID: UUID?
        var folderID: UUID?
        var parentID: UUID?
    }

    private nonisolated struct SplitTreeRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
        static let databaseTableName = "sessionSplitTree"

        var id: UUID
        var position: Int
        var tree: String
    }

    private nonisolated struct SplitPaneRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
        static let databaseTableName = "sessionSplitPane"

        var tabID: UUID
        var splitID: UUID
        var rowIndex: Int
        var columnIndex: Int
        var rowFraction: Double
        var columnFraction: Double
    }

    private nonisolated struct SessionSnapshot: Sendable {
        var tabs: [TabRecord]
        var folders: [FolderRecord]
        var items: [ItemRecord]
        var splits: [SplitTreeRecord]
        var restated: Set<UUID>
    }

    func cancelPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        saveWaitingSince = nil
    }

    nonisolated static func saveDelay(
        waiting: Duration,
        debounce: Duration,
        deadline: Duration
    ) -> Duration {
        max(.zero, min(debounce, deadline - waiting))
    }

    func scheduleSave(now: ContinuousClock.Instant = ContinuousClock.now) {
        let since = saveWaitingSince ?? now
        saveWaitingSince = since
        let delay = Self.saveDelay(
            waiting: since.duration(to: now),
            debounce: saveDebounce,
            deadline: saveDeadline
        )
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveWaitingSince = nil
        let snapshot = snapshot()
        let database = database
        let queued = saveChain
        saveChain = Task { [weak self] in
            _ = await queued?.value
            do {
                try await database.writer.write { db in
                    try Self.persist(snapshot, in: db)
                }
            } catch {
                Pipeline.log.error("session: write failed: \(error, privacy: .public)")
                self?.forgetWrittenState(of: snapshot)
            }
        }
    }

    var hasPendingSave: Bool {
        saveTask != nil
    }

    func saveBlocking() {
        cancelPendingSave()
        for tab in tabs {
            tab.invalidateSessionState()
        }
        let snapshot = snapshot()
        do {
            try database.writer.write { db in
                try Self.persist(snapshot, in: db)
            }
            Pipeline.log.notice("session: wrote \(snapshot.tabs.count) tabs, \(snapshot.folders.count) folders")
        } catch {
            Pipeline.log.error("session: final write failed: \(error, privacy: .public)")
            forgetWrittenState(of: snapshot)
        }
    }

    private func forgetWrittenState(of snapshot: SessionSnapshot) {
        for id in snapshot.restated {
            writtenStateGeneration[id] = nil
        }
    }

    private func snapshot() -> SessionSnapshot {
        let persisted = tabs.filter {
            $0.extensionBaseURL == nil && (!$0.isPrivate || (opensPrivately && database.isEphemeral))
        }
        var restated: Set<UUID> = []
        let tabRecords = persisted.map { tab -> TabRecord in
            let isRestated = writtenStateGeneration[tab.id] != tab.sessionStateGeneration
            if isRestated {
                restated.insert(tab.id)
                writtenStateGeneration[tab.id] = tab.sessionStateGeneration
            }
            return TabRecord(
                id: tab.id,
                title: tab.title,
                url: tab.urlString,
                state: isRestated ? tab.sessionState : nil,
                pinnedURL: tab.pinnedURL,
                pinnedTitle: tab.pinnedTitle.isEmpty ? nil : tab.pinnedTitle,
                internalPage: tab.internalPage,
                isActive: tab.id == activeTabID
            )
        }
        writtenStateGeneration = writtenStateGeneration.filter { id, _ in
            persisted.contains { $0.id == id }
        }

        let folderRecords = folders.enumerated().map { position, folder in
            FolderRecord(
                id: folder.id,
                position: position,
                name: folder.name,
                color: folder.color,
                isExpanded: folder.isExpanded
            )
        }
        let known = Set(persisted.map(\.id))
        let tree = reconciledTree()
        var itemRecords: [ItemRecord] = []
        func write(_ parent: UUID?) {
            for item in tree.rows(in: parent) {
                switch item {
                case .tab(let id):
                    guard known.contains(id) else { continue }
                    itemRecords.append(ItemRecord(
                        position: itemRecords.count, tabID: id, folderID: nil, parentID: parent
                    ))
                case .folder(let id):
                    itemRecords.append(ItemRecord(
                        position: itemRecords.count, tabID: nil, folderID: id, parentID: parent
                    ))
                    write(id)
                }
            }
        }
        write(nil)

        let encoder = JSONEncoder()
        let splitRecords = splits.reconciled(against: known).splits.enumerated().compactMap { position, split -> SplitTreeRecord? in
            guard let tree = try? encoder.encode(split.root),
                  let text = String(data: tree, encoding: .utf8)
            else { return nil }
            return SplitTreeRecord(id: split.leader ?? UUID(), position: position, tree: text)
        }

        return SessionSnapshot(
            tabs: tabRecords,
            folders: folderRecords,
            items: itemRecords,
            splits: splitRecords,
            restated: restated
        )
    }

    private nonisolated static func persist(_ snapshot: SessionSnapshot, in db: Database) throws {
        try FolderRecord.deleteAll(db)
        for folder in snapshot.folders {
            try folder.insert(db)
        }

        let keptIDs = snapshot.tabs.map(\.id)
        try TabRecord
            .filter(!keptIDs.contains(Column("id")))
            .deleteAll(db)

        for tab in snapshot.tabs {
            let writesState = snapshot.restated.contains(tab.id)
            try db.execute(
                sql: """
                    INSERT INTO sessionTab
                        (id, title, url, state, pinnedURL, pinnedTitle,
                         internalPage, isActive)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        title = excluded.title,
                        url = excluded.url,
                        \(writesState ? "state = excluded.state," : "")
                        pinnedURL = excluded.pinnedURL,
                        pinnedTitle = excluded.pinnedTitle,
                        internalPage = excluded.internalPage,
                        isActive = excluded.isActive
                    """,
                arguments: [
                    tab.id, tab.title, tab.url, tab.state, tab.pinnedURL, tab.pinnedTitle,
                    tab.internalPage?.rawValue, tab.isActive,
                ]
            )
        }

        try ItemRecord.deleteAll(db)
        for item in snapshot.items {
            try item.insert(db)
        }

        do {
            try SplitTreeRecord.deleteAll(db)
            for grid in snapshot.splits {
                try grid.insert(db)
            }
            try SplitPaneRecord.deleteAll(db)
        } catch {
            Pipeline.log.error("session: split write failed: \(error, privacy: .public)")
        }
    }

    func dressRow(_ tab: BrowserTab, fromHost host: String) {
        if tab.isPrivate {
            if let icon = FaviconLoader.shared.cached(for: host) {
                tab.favicon = icon
            }
            return
        }
        Task { [weak tab] in
            let icon = await FaviconLoader.shared.load(forHost: host)
            guard let tab, let icon,
                  URL(string: tab.urlString)?.host()?.lowercased() == host.lowercased()
            else { return }
            tab.favicon = icon
        }
    }

    func restoreSession() {
        guard tabs.isEmpty else { return }

        let stored = try? database.writer.read { db in
            (
                tabs: try TabRecord.fetchAll(db),
                folders: try FolderRecord.fetchAll(db),
                items: try ItemRecord.order(Column("position")).fetchAll(db)
            )
        }
        guard let stored, !stored.tabs.isEmpty else { return }

        let storedTrees = (try? database.writer.read { db in
            try SplitTreeRecord.order(Column("position")).fetchAll(db)
        }) ?? []
        let storedPanes = storedTrees.isEmpty
            ? (try? database.writer.read { db in
                try SplitPaneRecord
                    .order(Column("rowIndex"), Column("columnIndex"))
                    .fetchAll(db)
            }) ?? []
            : []

        let byID = Dictionary(stored.tabs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var ordered: [TabRecord] = []
        var seen: Set<UUID> = []
        for item in stored.items {
            guard let id = item.tabID, let record = byID[id], seen.insert(id).inserted else { continue }
            ordered.append(record)
        }
        for record in stored.tabs where seen.insert(record.id).inserted {
            ordered.append(record)
        }

        let activeIndex = ordered.firstIndex { $0.isActive } ?? 0
        let activeID = ordered[activeIndex].id
        let grids = Self.grids(from: storedTrees) + Self.grids(fromFlat: storedPanes)
        let onScreen = Set(
            [activeID] + (grids.first { $0.contains(activeID) }?.tabs ?? [])
        )

        for record in ordered {
            let restoredURL = record.url.isEmpty
                ? record.internalPage?.url
                : URL(string: record.url)
            let tab = makeTab(
                for: restoredURL,
                id: record.id,
                restoring: !onScreen.contains(record.id)
            )
            tab.title = record.title
            tab.urlString = restoredURL.map(\.absoluteString) ?? record.url
            tab.pinnedURL = record.pinnedURL
            tab.pinnedTitle = record.pinnedTitle ?? ""
            tab.deferRestore(state: record.state, url: restoredURL)
            if let host = URL(string: record.url)?.host() {
                dressRow(tab, fromHost: host)
            }
            tabs.append(tab)
            writtenStateGeneration[tab.id] = tab.sessionStateGeneration
            onTabOpened?(tab)
        }

        var foldersByStoredID: [UUID: TabFolder] = [:]
        for record in stored.folders {
            let folder = TabFolder(name: record.name)
            folder.color = record.color
            folder.isExpanded = record.isExpanded
            foldersByStoredID[record.id] = folder
            folders.append(folder)
        }

        var root: [SidebarItem] = []
        var children: [UUID: [SidebarItem]] = [:]
        for record in stored.items {
            let item: SidebarItem
            if let id = record.tabID, byID[id] != nil {
                item = .tab(id)
            } else if let id = record.folderID, let folder = foldersByStoredID[id] {
                item = .folder(folder.id)
            } else {
                continue
            }
            if let parentID = record.parentID {
                guard let parent = foldersByStoredID[parentID] else { continue }
                children[parent.id, default: []].append(item)
            } else {
                root.append(item)
            }
        }
        storedTree = SidebarTree(root: root, children: children)
        splits = TabSplits(grids)
        sidebarDidChange()

        activeTabID = tabs[min(activeIndex, tabs.count - 1)].id
        for pane in activeTab.map({ splitOthers(of: $0) }) ?? [] {
            pane.realizeDeferredSession()
        }
        Pipeline.log.notice(
            "session: restored \(self.tabs.count) of \(stored.tabs.count) stored tabs, \(self.folders.count) folders"
        )
    }

    private nonisolated static func grids(from records: [SplitTreeRecord]) -> [TabSplit] {
        let decoder = JSONDecoder()
        return records.compactMap { record in
            guard let data = record.tree.data(using: .utf8),
                  let root = try? decoder.decode(SplitNode.self, from: data)
            else { return nil }
            return TabSplit(root: root)
        }
    }

    private nonisolated static func grids(fromFlat panes: [SplitPaneRecord]) -> [TabSplit] {
        Dictionary(grouping: panes, by: \.splitID)
            .sorted { ($0.value.first?.tabID.uuidString ?? "") < ($1.value.first?.tabID.uuidString ?? "") }
            .compactMap { _, panes in
                let byRow = Dictionary(grouping: panes, by: \.rowIndex)
                let rowFraction = CGFloat(panes.first?.rowFraction ?? 0.5)
                let lines = byRow.keys.sorted().compactMap { index -> SplitNode? in
                    guard let line = byRow[index] else { return nil }
                    let ordered = line.sorted { $0.columnIndex < $1.columnIndex }
                    let fraction = CGFloat(ordered.first?.columnFraction ?? 0.5)
                    let pages = ordered.enumerated().map { column, pane in
                        SplitNode.page(pane.tabID, share: column == 0 ? fraction : 1 - fraction)
                    }
                    guard pages.count > 1 else { return pages.first }
                    return .group(.sideBySide, pages)
                }
                guard lines.count > 1 else { return lines.first.flatMap(TabSplit.init(root:)) }
                let stacked = lines.enumerated().map { index, line -> SplitNode in
                    SplitNode(line.content, share: index == 0 ? rowFraction : 1 - rowFraction)
                }
                return TabSplit(root: .group(.stacked, stacked))
            }
    }

    func tab(matching reference: String) -> BrowserTab? {
        let needle = reference.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        return tabs.first {
            $0.title.lowercased().contains(needle) || $0.urlString.lowercased().contains(needle)
        }
    }

    @discardableResult
    func ensureActiveTab() -> BrowserTab {
        if let activeTab {
            return activeTab
        }
        return newTab()
    }

    // MARK: - Profiles

    func closeAllTabs(saving: Bool = true) {
        if saving {
            saveBlocking()
        }
        for tab in tabs {
            tab.webView.stopLoading()
            tab.detach()
            tab.webView.removeFromSuperview()
        }
        tabs = []
        folders = []
        storedTree = SidebarTree()
        splits = TabSplits()
        activeTabID = nil
        closedTabs = []
        lastVisitID = [:]
        recentlyActive = []
        writtenStateGeneration = [:]
        sidebarDidChange()
        cancelPendingSave()
    }

    func adopt(
        database: AppDatabase,
        sitePermissions: SitePermissions,
        privately: Bool = false
    ) {
        cancelPendingSave()
        if privately, !database.isEphemeral {
            Pipeline.log.error("profile: a private model refused a persistent database")
            self.database = .temporary()
        } else {
            self.database = database
        }
        self.sitePermissions = sitePermissions
        opensPrivately = privately
        history = HistoryStore(database: self.database)
        history.prune(retention: BrowserSettings.shared.historyRetention)
    }
}
