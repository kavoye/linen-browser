// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

extension BrowserModel {
    // MARK: - Pinning

    func pin(_ tab: BrowserTab) {
        guard let url = URL(string: tab.urlString), !tab.urlString.isEmpty else { return }
        tab.pinnedURL = url
        tab.pinnedTitle = tab.title
        scheduleSave()
    }

    func unpin(_ tab: BrowserTab) {
        tab.pinnedURL = nil
        tab.pinnedTitle = ""
        scheduleSave()
    }

    func returnToPin(_ tab: BrowserTab) {
        guard let url = tab.pinnedURL else { return }
        activeTabID = tab.id
        tab.load(url)
    }

    // MARK: - Split view

    var activeSplit: TabSplit? {
        guard let activeTabID else { return nil }
        return splits.split(containing: activeTabID)
    }

    var splitPanes: [BrowserTab]? {
        guard let split = activeSplit else { return nil }
        let resolved = split.tabs.compactMap { tabsByID[$0] }
        return resolved.count == split.count ? resolved : nil
    }

    func isVisibleInSplit(_ tab: BrowserTab) -> Bool {
        activeSplit?.contains(tab.id) == true
    }

    func spaceID(of tabID: UUID) -> UUID {
        splits.split(containing: tabID)?.leader ?? tabID
    }

    var activeSpaceID: UUID? {
        activeTabID.map(spaceID(of:))
    }

    func spaceTabs(_ spaceID: UUID) -> [BrowserTab] {
        guard let split = splits.splitLed(by: spaceID) else {
            return tabsByID[spaceID].map { [$0] } ?? []
        }
        return split.tabs.compactMap { tabsByID[$0] }
    }

    func splitOthers(of tab: BrowserTab) -> [BrowserTab] {
        splits.others(of: tab.id).compactMap { tabsByID[$0] }
    }

    func splitFollowers(of tab: BrowserTab) -> [BrowserTab]? {
        guard let split = splits.splitLed(by: tab.id) else { return nil }
        let resolved = split.tabs.dropFirst().compactMap { tabsByID[$0] }
        return resolved.count == split.count - 1 ? resolved : nil
    }

    var hiddenSidebarTabIDs: Set<UUID> {
        splits.followerTabs
    }

    func withSplitMembers(_ items: [SidebarItem]) -> [SidebarItem] {
        items.flatMap { item -> [SidebarItem] in
            guard case .tab(let id) = item, let split = splits.splitLed(by: id) else { return [item] }
            return split.tabs.map(SidebarItem.tab)
        }
    }

    func refreshTopBarCoverage() {
        let split = paneInAir == nil ? activeSplit : nil
        for tab in tabs {
            guard let split, split.contains(tab.id) else {
                tab.isUnderTopBar = true
                continue
            }
            tab.isUnderTopBar = split.isUnderTopBar(tab.id)
        }
    }

    func split(_ anchor: BrowserTab, with tab: BrowserTab, axis: SplitAxis) {
        guard anchor !== tab else { return }
        splits = splits.splitting(anchor.id, with: tab.id, axis: axis)
        settleSplit(containing: anchor)
    }

    func insertIntoSplit(_ tab: BrowserTab, beside anchor: BrowserTab, edge: SplitDropZone) {
        guard anchor !== tab else { return }
        splits = splits.inserting(tab.id, beside: anchor.id, edge: edge)
        settleSplit(containing: anchor)
    }

    func moveSplitPane(_ tab: BrowserTab, beside anchor: BrowserTab, edge: SplitDropZone) {
        guard anchor !== tab else { return }
        splits = splits.moving(tab.id, beside: anchor.id, edge: edge)
        settleSplit(containing: anchor)
    }

    func replaceSplitPane(_ replaced: BrowserTab, with tab: BrowserTab) {
        splits = splits.replacing(replaced.id, with: tab.id)
        settleSplit(containing: tab)
    }

    func removeFromSplit(_ tab: BrowserTab) {
        guard let survivor = splits.others(of: tab.id).first.flatMap({ tabsByID[$0] }) else { return }
        splits = splits.removing(tab.id)
        settleSplit(containing: survivor)
    }

    func dissolveSplit(containing tab: BrowserTab) {
        guard splits.contains(tab.id) else { return }
        splits = splits.dissolving(containing: tab.id)
        refreshTopBarCoverage()
        scheduleSave()
    }

    func swapSplitRow(containing tab: BrowserTab) {
        splits = splits.swappingRow(containing: tab.id)
        settleSplit(containing: tab)
    }

    func setSplitAxis(_ axis: SplitAxis, containing tab: BrowserTab) {
        splits = splits.setting(axis: axis, containing: tab.id)
        settleSplit(containing: tab)
    }

    func setSplitSeam(_ seam: SplitSeam, containing tab: BrowserTab, leading: CGFloat, minimum: CGFloat) {
        splits = splits.setting(
            seam: seam.index,
            inGroupAt: seam.groupPath,
            containing: tab.id,
            leading: leading,
            minimum: minimum
        )
    }

    private func settleSplit(containing tab: BrowserTab) {
        if let split = splits.split(containing: tab.id) {
            gather(split.tabs)
        }
        refreshTopBarCoverage()
        reconcileSpaces()
        scheduleSave()
    }

    private func gather(_ ids: [UUID]) {
        guard let leader = ids.first else { return }
        let tree = reconciledTree()
        let anchor = SidebarItem.tab(leader)
        let followers = ids.dropFirst().map(SidebarItem.tab)
        guard !followers.isEmpty else { return }
        move(
            followers,
            into: tree.parent(of: anchor).flatMap(folder(id:)),
            before: tree.successor(of: anchor)
        )
    }

    func close(_ tab: BrowserTab, recordForReopening: Bool = true) {
        if recordForReopening, !tab.isPrivate {
            closedTabs.append(ClosedTab(
                title: tab.title,
                url: tab.urlString,
                state: tab.sessionState,
                folderID: folder(containing: tab)?.id,
                index: tabs.firstIndex { $0 === tab } ?? 0
            ))
            if closedTabs.count > Self.closedTabMemory {
                closedTabs.removeFirst()
            }
        }

        let survivor = splits.others(of: tab.id).first.flatMap { tabsByID[$0] }
        splits = splits.removing(tab.id)
        if activeTabID == tab.id {
            activeTabID = (survivor ?? neighbor(of: tab))?.id
        }
        tabs.removeAll { $0 === tab }
        storedTree = reconciledTree().removing([.tab(tab.id)])
        sidebarDidChange()
        lastVisitID[tab.id] = nil
        recentlyActive.removeAll { $0 == tab.id }
        onTabClosed?(tab)
        scheduleSave()

        tab.webView.stopLoading()
        tab.webView.load(URLRequest(url: URL(string: "about:blank")!))
        tab.webView.removeFromSuperview()
    }

    private func neighbor(of tab: BrowserTab) -> BrowserTab? {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else {
            return tabs.first { $0 !== tab }
        }
        let hidden = hiddenSidebarTabIDs
        let below = tabs[tabs.index(after: index)...]
        let above = tabs[..<index].reversed()
        return below.first { !hidden.contains($0.id) }
            ?? above.first { !hidden.contains($0.id) }
            ?? below.first
            ?? above.first
    }

    static func isPlayingMedia(_ webView: WKWebView) async -> Bool {
        let script = """
        !!Array.from(document.querySelectorAll('video, audio'))
            .find(m => !m.paused && !m.ended && m.currentTime > 0
                       && !m.muted && m.volume > 0)
        """
        return (try? await webView.evaluateJavaScript(script)) as? Bool ?? false
    }

    func closeOthers(_ kept: BrowserTab) {
        for tab in tabs.reversed() where tab !== kept {
            close(tab)
        }
    }

    func closeActiveTab() {
        if let activeTab {
            close(activeTab)
        }
    }

    func activate(_ tab: BrowserTab) {
        activeTabID = tab.id
        scheduleSave()
    }

    // MARK: - Reopening and cycling

    struct ClosedTab {
        let title: String
        let url: String
        let state: Data?
        let folderID: UUID?
        let index: Int
    }

    private static let closedTabMemory = 20

    var canReopenClosedTab: Bool {
        !closedTabs.isEmpty
    }

    func reopenLastClosedTab() {
        guard let record = closedTabs.popLast() else { return }
        let tab = makeTab(for: URL(string: record.url))
        tab.title = record.title
        tab.urlString = record.url
        if let state = record.state {
            tab.webView.interactionState = state
        } else if let url = URL(string: record.url) {
            tab.load(url)
        }
        let at = min(record.index, tabs.count)
        tabs.insert(tab, at: at)
        if let folderID = record.folderID, folders.contains(where: { $0.id == folderID }) {
            place([.tab(tab.id)], in: folderID, before: nil)
        } else if at > 0 {
            storedTree = reconciledTree().inserting(.tab(tab.id), after: .tab(tabs[at - 1].id))
        } else {
            place([.tab(tab.id)], in: nil, before: reconciledTree().root.first)
        }
        sidebarDidChange()
        onTabOpened?(tab)
        activeTabID = tab.id
        scheduleSave()
    }

    func activateTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        activate(tabs[index])
    }

    func activateLastTab() {
        if let last = tabs.last {
            activate(last)
        }
    }

    func cycleTab(forward: Bool) {
        guard tabs.count > 1, let current = tabs.firstIndex(where: { $0.id == activeTab?.id }) else { return }
        let next = forward
            ? (current + 1) % tabs.count
            : (current - 1 + tabs.count) % tabs.count
        activate(tabs[next])
    }

    // MARK: - Folders

    static let defaultFolderName = String(localized: "New Folder")

    @discardableResult
    func createFolder(named name: String = defaultFolderName, containing items: [SidebarItem] = []) -> TabFolder {
        let tree = reconciledTree()
        let order = tree.walk()
        let topmost = tree.normalized(items).min {
            (order.firstIndex(of: $0) ?? .max) < (order.firstIndex(of: $1) ?? .max)
        }
        let folder = TabFolder(name: name)
        folders.append(folder)
        storedTree = tree.moving(
            [.folder(folder.id)],
            into: topmost.flatMap { tree.parent(of: $0) },
            before: topmost ?? tree.root.first
        ) ?? tree
        sidebarDidChange()
        if !items.isEmpty {
            move(items, into: folder)
            autoName(folder)
        }
        scheduleSave()
        return folder
    }

    @discardableResult
    func createFolder(named name: String = defaultFolderName, containing tabs: [BrowserTab]) -> TabFolder {
        createFolder(named: name, containing: tabs.map { .tab($0.id) })
    }

    func autoName(_ folder: TabFolder) {
        guard folder.name == Self.defaultFolderName, FolderNamer.isAvailable else { return }
        let titles = tabs(in: folder).map(\.title)
        Task { [weak self, weak folder] in
            guard let suggestion = await FolderNamer.suggestName(forTitles: titles) else { return }
            guard let self, let folder,
                  folders.contains(where: { $0 === folder }),
                  folder.name == Self.defaultFolderName
            else { return }
            folder.name = suggestion
            scheduleSave()
        }
    }

    func renameFolder(_ folder: TabFolder, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        folder.name = trimmed
        scheduleSave()
    }

    func setFolderColor(_ color: TabFolderColor, for folder: TabFolder) {
        guard folder.color != color else { return }
        folder.color = color
        scheduleSave()
    }

    func deleteFolder(_ folder: TabFolder) {
        storedTree = reconciledTree().dissolving(folder.id)
        folders.removeAll { $0 === folder }
        syncTabOrder()
        scheduleSave()
    }

    func move(_ tab: BrowserTab, to folder: TabFolder?) {
        if let folder {
            move([.tab(tab.id)], into: folder)
        } else {
            moveOut([.tab(tab.id)])
        }
    }

    func move(_ items: [SidebarItem], into folder: TabFolder?, before target: SidebarItem? = nil) {
        let tree = reconciledTree()
        let moved = tree.normalized(items)
        guard !moved.isEmpty, let next = tree.moving(moved, into: folder?.id, before: target) else { return }
        storedTree = next
        if let folder {
            folder.isExpanded = true
            autoName(folder)
        }
        syncTabOrder()
        scheduleSave()
    }

    func moveOut(_ items: [SidebarItem]) {
        let tree = reconciledTree()
        let moved = tree.normalized(items)
        guard let first = moved.first, let left = tree.parent(of: first) else { return }
        let folder = SidebarItem.folder(left)
        guard let next = tree.moving(moved, into: tree.parent(of: folder), before: tree.successor(of: folder))
        else { return }
        storedTree = next
        syncTabOrder()
        scheduleSave()
    }

    func close(_ items: [SidebarItem]) {
        let all = sidebarTree.expanded(Set(items))
        for case .tab(let id) in all {
            if let tab = tabsByID[id] {
                close(tab)
            }
        }
        for case .folder(let id) in all {
            if let folder = foldersByID[id] {
                deleteFolder(folder)
            }
        }
    }

    /// Every tab the selection reaches, folders included, in sidebar order.
    func tabs(under items: [SidebarItem]) -> [BrowserTab] {
        let wanted = sidebarTree.expanded(Set(items))
        return sidebarTree.walk().compactMap { item in
            guard wanted.contains(item), case .tab(let id) = item else { return nil }
            return tabsByID[id]
        }
    }

    func tabCount(in items: [SidebarItem]) -> Int {
        sidebarTree.expanded(Set(items)).filter { if case .tab = $0 { true } else { false } }.count
    }

    func folder(id: UUID) -> TabFolder? {
        foldersByID[id]
    }

    func folder(containing tab: BrowserTab) -> TabFolder? {
        sidebarTree.parent(of: .tab(tab.id)).flatMap(folder(id:))
    }

    func folder(containing folder: TabFolder) -> TabFolder? {
        sidebarTree.parent(of: .folder(folder.id)).flatMap(folder(id:))
    }

    var sidebarItems: [SidebarItem] {
        sidebarTree.root
    }

    func reconciledTree() -> SidebarTree {
        SidebarTree.reconcile(stored: storedTree, folders: folders.map(\.id), tabs: tabs.map(\.id))
    }

    func place(_ items: [SidebarItem], in parent: UUID?, before target: SidebarItem?) {
        guard let next = reconciledTree().moving(items, into: parent, before: target) else { return }
        storedTree = next
    }

    func tab(id: UUID) -> BrowserTab? {
        tabsByID[id]
    }

    func sidebarDidChange() {
        tabsByID = Dictionary(tabs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        foldersByID = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        sidebarTree = reconciledTree()
        splits = splits.reconciled(against: Set(tabsByID.keys))
        reconcileSpaces()
    }

    private func reconcileSpaces() {
        let current = Dictionary(tabs.map { ($0.id, spaceID(of: $0.id)) }, uniquingKeysWith: { first, _ in first })
        let previous = spaceAnchors
        spaceAnchors = current
        guard !previous.isEmpty, let onSpaceAnchorChanged else { return }

        let names = Set(current.values)
        for name in Set(previous.values) where !names.contains(name) {
            let members = previous.filter { $0.value == name }.keys
            let successors = Set(members.compactMap { current[$0] })
            guard successors.count == 1, let successor = successors.first, successor != name else { continue }
            onSpaceAnchorChanged(name, successor)
        }
    }

    private func syncTabOrder() {
        let byID = Dictionary(tabs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = reconciledTree().flattenedTabs(known: Set(byID.keys))
        let placed = Set(ordered)
        tabs = ordered.compactMap { byID[$0] } + tabs.filter { !placed.contains($0.id) }
        sidebarDidChange()
    }

    func rows(in folder: TabFolder?) -> [SidebarItem] {
        sidebarTree.rows(in: folder?.id)
    }

    func tabs(in folder: TabFolder) -> [BrowserTab] {
        rows(in: folder).compactMap { item in
            guard case .tab(let id) = item else { return nil }
            return tabsByID[id]
        }
    }

    func allTabs(in folder: TabFolder) -> [BrowserTab] {
        sidebarTree.descendants(ofFolder: folder.id).compactMap { item in
            guard case .tab(let id) = item else { return nil }
            return tabsByID[id]
        }
    }

    var ungroupedTabs: [BrowserTab] {
        sidebarTree.root.compactMap { item in
            guard case .tab(let id) = item else { return nil }
            return tabsByID[id]
        }
    }
}
