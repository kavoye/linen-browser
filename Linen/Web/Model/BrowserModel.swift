// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import GRDB
import Observation
import os
import SwiftUI
import WebKit

@MainActor
@Observable
final class BrowserModel {
    var tabs: [BrowserTab] = []
    var folders: [TabFolder] = []
    var storedTree = SidebarTree()
    var history: HistoryStore
    var sitePermissions: SitePermissions
    let downloads: DownloadManager

    init(
        database: AppDatabase = .shared,
        history: HistoryStore? = nil,
        sitePermissions: SitePermissions = .shared,
        downloads: DownloadManager = DownloadManager()
    ) {
        self.database = database
        self.history = history ?? HistoryStore(database: database)
        self.sitePermissions = sitePermissions
        self.downloads = downloads
    }
    let sidebarSelection = SidebarSelection()

    var activeTabID: UUID? {
        didSet {
            guard oldValue != activeTabID else { return }
            sidebarSelection.dropMarks()
            if let activeTabID {
                noteActivation(activeTabID)
            }
            let previous = oldValue.flatMap { id in tabs.first { $0.id == id } }
            refreshTopBarCoverage()
            if previous.map({ !isVisibleInSplit($0) }) ?? false {
                previous?.refreshPreview()
                previous?.noteHoveredLink(nil)
            }
            activeTab?.realizeDeferredSession()
            for id in activeSplit?.tabs ?? [] {
                tabsByID[id]?.realizeDeferredSession()
            }
            activeTab?.measureBandUnderBar()
            onActiveTabChanged?(activeTab, previous)
        }
    }
    var extensionPageHost: ((URL) -> ExtensionPageHost?)?
    var onTabOpened: ((BrowserTab) -> Void)?
    var onNavigationStarted: ((BrowserTab, URL) -> Void)?
    var onTabClosed: ((BrowserTab) -> Void)?
    var onActiveTabChanged: ((BrowserTab?, BrowserTab?) -> Void)?
    var onSpaceAnchorChanged: ((UUID, UUID) -> Void)?
    var onContentProcessTerminated: ((BrowserTab) -> Void)?
    var onPictureInPictureChanged: ((BrowserTab, Bool) -> Void)?
    var onLinkHovered: ((BrowserTab, URL?, NSEvent.ModifierFlags, CGPoint) -> Void)?
    var onOpenInPeek: ((BrowserTab?, URL, CGPoint) -> Void)?
    var onPictureReturnExpected: ((BrowserTab) -> Void)?

    var activeTab: BrowserTab? {
        guard let activeTabID else { return tabs.first }
        return tabsByID[activeTabID] ?? tabs.first
    }
    // MARK: - Tab management

    func makeTab(
        for url: URL? = nil,
        id: UUID = UUID(),
        adopting: WKWebView? = nil,
        restoring: Bool = false
    ) -> BrowserTab {
        let privately = opensPrivately
        let tab = BrowserTab(
            id: id,
            extensionHost: adopting == nil ? url.flatMap { extensionPageHost?($0) } : nil,
            adopting: adopting,
            restoring: restoring,
            opensBlank: url == nil,
            privately: privately,
            sitePermissions: sitePermissions
        )
        tab.onNavigationStarted = { [weak self, weak tab] url in
            guard let tab else { return }
            self?.onNavigationStarted?(tab, url)
        }
        tab.onNavigationFinished = { [weak self, weak tab] wasRestore in
            self?.scheduleSave()
            guard !wasRestore, let tab, !tab.isPrivate else { return }
            self?.recordVisit(for: tab)
        }
        tab.onSameDocumentNavigation = { [weak self] in
            self?.scheduleSave()
        }
        tab.onContentProcessTerminated = { [weak self, weak tab] in
            guard let tab else { return }
            self?.onContentProcessTerminated?(tab)
        }
        tab.onNavigationOutsideExtension = { [weak self] url in
            self?.newTab(url: url)
        }
        tab.onNewWindow = { [weak self, weak tab] view, activate in
            let opened = self?.newTab(activate: activate, adopting: view, after: tab)
            guard let self, let opened, let tab, let origin = lastVisitID[tab.id] else { return }
            lastVisitID[opened.id] = origin
        }
        tab.onOpenInNewTab = { [weak self, weak tab] url, activate in
            guard let self else { return }
            let opened = newTab(url: url, activate: activate, after: tab, transition: .link)
            guard let tab, let origin = lastVisitID[tab.id] else { return }
            lastVisitID[opened.id] = origin
        }
        tab.onOpenInPeek = { [weak self, weak tab] url, origin in
            self?.onOpenInPeek?(tab, url, origin)
        }
        tab.onCloseRequested = { [weak self, weak tab] in
            guard let tab else { return }
            self?.close(tab)
        }
        tab.onPictureInPictureChanged = { [weak self, weak tab] isOut in
            guard let tab else { return }
            self?.onPictureInPictureChanged?(tab, isOut)
        }
        tab.onLinkHovered = { [weak self, weak tab] url, modifiers, anchor in
            guard let tab else { return }
            self?.onLinkHovered?(tab, url, modifiers, anchor)
        }
        tab.onPictureReturnExpected = { [weak self, weak tab] in
            guard let tab else { return }
            self?.onPictureReturnExpected?(tab)
        }
        tab.onDownload = { [weak self, weak tab] download, source in
            self?.downloads.adopt(
                download,
                suggestedSource: source,
                sourceTabID: tab?.id,
                privately: tab?.isPrivate ?? false
            )
        }
        if tab.isMaterialised {
            BrowserSettings.shared.apply(to: tab.webView)
        }
        return tab
    }

    var lastVisitID: [UUID: Int64] = [:]

    private func recordVisit(for tab: BrowserTab) {
        guard !tab.isPrivate, !tab.isClosed, tabsByID[tab.id] === tab else { return }
        let visitID = history.record(
            url: tab.urlString,
            title: tab.title,
            transition: tab.pendingTransition,
            fromVisit: lastVisitID[tab.id]
        )
        guard let visitID else { return }
        lastVisitID[tab.id] = visitID
    }

    var recentlyActive: [UUID] = []

    var switcherRecency: [UUID]?

    private func noteActivation(_ id: UUID) {
        recentlyActive.removeAll { $0 == id }
        recentlyActive.insert(id, at: 0)
        if recentlyActive.count > 32 {
            recentlyActive.removeLast(recentlyActive.count - 32)
        }
    }

    @discardableResult
    func newTab(
        url: URL? = nil,
        activate: Bool = true,
        adopting: WKWebView? = nil,
        after opener: BrowserTab? = nil,
        transition: HistoryStore.Transition = .typed
    ) -> BrowserTab {
        let url = adopting == nil ? (url ?? BrowserSettings.shared.newTabURL) : url
        let tab = makeTab(for: url, adopting: adopting)
        insert(tab, after: opener)
        onTabOpened?(tab)
        if activate {
            activeTabID = tab.id
        }
        if let url {
            tab.load(url, transition: transition)
        }
        scheduleSave()
        return tab
    }

    private func insert(_ tab: BrowserTab, after opener: BrowserTab?) {
        let keptRun = keptRunAtTop()
        if let anchor = opener.flatMap(insertionAnchor(after:)),
           !keptRun.contains(.tab(anchor.id)),
           let index = tabs.firstIndex(where: { $0 === anchor }) {
            tabs.insert(tab, at: tabs.index(after: index))
            storedTree = reconciledTree().inserting(.tab(tab.id), after: .tab(anchor.id))
        } else if let kept = keptRun.last {
            tabs.insert(tab, at: 0)
            storedTree = reconciledTree().inserting(.tab(tab.id), after: kept)
            syncTabOrder()
        } else {
            tabs.insert(tab, at: 0)
            place([.tab(tab.id)], in: nil, before: reconciledTree().root.first)
        }
        sidebarDidChange()
    }

    // MARK: - Peek

    /// A peeked page is a tab no list holds: it reaches neither the sidebar,
    /// the session file nor the extensions until you keep it.
    func makePeekTab(_ url: URL) -> BrowserTab {
        let tab = makeTab(for: url)
        tab.onOpenInPeek = nil
        tab.load(url, transition: .link)
        return tab
    }

    func keepPeekTab(_ tab: BrowserTab, after opener: BrowserTab?) {
        insert(tab, after: opener)
        onTabOpened?(tab)
        activeTabID = tab.id
        scheduleSave()
    }

    func keepPeekTab(_ tab: BrowserTab, besidePage anchor: BrowserTab) {
        keepPeekTab(tab, after: anchor)
        guard splits.split(containing: anchor.id)?.isFull != true else { return }
        if splits.contains(anchor.id) {
            insertIntoSplit(tab, beside: anchor, edge: .right)
        } else {
            split(anchor, with: tab, axis: .sideBySide)
        }
        activate(tab)
    }

    func dismissPeekTab(_ tab: BrowserTab) {
        if tab.isMaterialised {
            tab.webView.stopLoading()
            tab.webView.load(URLRequest(url: URL(string: "about:blank")!))
            tab.webView.removeFromSuperview()
        }
        tab.detach()
    }

    private func insertionAnchor(after opener: BrowserTab) -> BrowserTab? {
        let space = Set(spaceTabs(spaceID(of: opener.id)).map(\.id))
        guard !space.isEmpty else { return tabs.contains { $0 === opener } ? opener : nil }
        return tabs.last { space.contains($0.id) }
    }

    @discardableResult
    func importBookmarksFolder(named name: String, entries: [HistoryStore.Entry]) -> TabFolder? {
        let imported = entries.compactMap { mark -> BrowserTab? in
            guard let url = URL(string: mark.url), url.scheme?.hasPrefix("http") == true else {
                return nil
            }
            let tab = makeTab(for: url, restoring: true)
            tab.title = mark.title
            tab.urlString = mark.url
            tab.deferRestore(state: nil, url: url)
            if let host = url.host() {
                dressRow(tab, fromHost: host)
            }
            tabs.append(tab)
            onTabOpened?(tab)
            return tab
        }
        sidebarDidChange()
        guard !imported.isEmpty else { return nil }
        let folder = createFolder(named: name, containing: imported)
        folder.isExpanded = false
        scheduleSave()
        return folder
    }

    @discardableResult
    func duplicate(_ tab: BrowserTab) -> BrowserTab {
        let copy = makeTab(for: URL(string: tab.urlString))
        copy.pageTitle = tab.pageTitle
        copy.customTitle = tab.customTitle
        copy.urlString = tab.urlString
        if let state = tab.webView.interactionState as? Data {
            copy.webView.interactionState = state
        } else if let url = URL(string: tab.urlString), !tab.urlString.isEmpty {
            copy.load(url)
        }
        copy.pinnedURL = tab.pinnedURL
        copy.pinnedTitle = tab.pinnedTitle

        let at = (tabs.firstIndex { $0 === tab }).map { $0 + 1 } ?? tabs.endIndex
        tabs.insert(copy, at: at)
        storedTree = reconciledTree().inserting(.tab(copy.id), after: .tab(tab.id))
        sidebarDidChange()
        onTabOpened?(copy)
        activeTabID = copy.id
        scheduleSave()
        return copy
    }

    var splits = TabSplits()

    var spaceAnchors: [UUID: UUID] = [:]

    var paneInAir: UUID? {
        didSet {
            guard paneInAir != oldValue else { return }
            refreshTopBarCoverage()
        }
    }

    var closedTabs: [ClosedTab] = []

    var sidebarTree = SidebarTree()

    var tabsByID: [UUID: BrowserTab] = [:]
    var foldersByID: [UUID: TabFolder] = [:]

    @ObservationIgnored var saveTask: Task<Void, Never>?

    @ObservationIgnored var saveChain: Task<Void, Never>?

    @ObservationIgnored var saveWaitingSince: ContinuousClock.Instant?

    @ObservationIgnored var saveDebounce: Duration = .seconds(2)

    @ObservationIgnored var saveDeadline: Duration = .seconds(8)

    var database: AppDatabase

    var writtenStateGeneration: [UUID: Int] = [:]

    var opensPrivately = false
}
