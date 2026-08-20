// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os
import WebKit

extension BrowserModel {
    // MARK: - Memory pressure

    private static let warningKeepsRecent = 3

    @discardableResult
    func discardBackgroundTabs(keepingRecent keep: Int = 0) -> Int {
        let spared = Set([activeTabID].compactMap { $0 } + recentlyActive.prefix(keep))
        var discarded = 0
        for tab in tabs where !spared.contains(tab.id)
            && tab.canDiscardWebContent
            && protectionReason(for: tab) == nil {
            tab.discardWebContent()
            discarded += 1
        }
        return discarded
    }

    func protectionReason(for tab: BrowserTab) -> TabProtectionReason? {
        if let reason = tab.intrinsicProtectionReason {
            return reason
        }
        if isVisibleInSplit(tab) {
            return .visibleInSplit
        }
        if downloads.hasActiveDownload(for: tab.id) {
            return .activeDownload
        }
        if keepsActive(tab) {
            return .alwaysKeepActive
        }
        return nil
    }

    func keepActiveOrigin(for tab: BrowserTab) -> String {
        guard let url = URL(string: tab.urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return "" }
        return SitePermissions.origin(for: url)
    }

    func keepsActive(_ tab: BrowserTab) -> Bool {
        let origin = keepActiveOrigin(for: tab)
        return !origin.isEmpty && sitePermissions.keepsActive(origin)
    }

    func setKeepsActive(_ keepsActive: Bool, for tab: BrowserTab) {
        let origin = keepActiveOrigin(for: tab)
        guard !origin.isEmpty else { return }
        sitePermissions.setKeepsActive(keepsActive, for: origin)
    }

    func relieveMemoryPressure(_ level: MemoryPressureMonitor.Level) {
        let keep = level == .critical ? 0 : Self.warningKeepsRecent
        let discarded = discardBackgroundTabs(keepingRecent: keep)
        guard discarded > 0 else { return }
        Pipeline.log.notice("memory pressure: discarded \(discarded, privacy: .public) background tabs")
    }

    func applyWebSettings() {
        let settings = BrowserSettings.shared
        for tab in tabs {
            settings.apply(to: tab.webView)
        }
        WebViewPool.shared.discardIdle()
    }

    // MARK: - The browser's own pages

    @discardableResult
    func showHistory() -> BrowserTab {
        show(.history)
    }

    @discardableResult
    func showDownloads() -> BrowserTab {
        show(.downloads)
    }

    @discardableResult
    func showReleaseNotes() -> BrowserTab {
        show(.releaseNotes)
    }

    @discardableResult
    private func show(_ page: BrowserTab.InternalPage) -> BrowserTab {
        sidebarSelection.dropMarks()
        let origin = activeTabID

        if let existing = tabs.first(where: { $0.internalPage == page }) {
            if origin != existing.id {
                internalReturn = InternalReturn(page: page, closesTab: false, previousTabID: origin)
            }
            activeTabID = existing.id
            return existing
        }

        let tab: BrowserTab
        if let active = activeTab, active.urlString.isEmpty, active.internalPage == nil {
            tab = active
            activeTabID = active.id
            internalReturn = InternalReturn(page: page, closesTab: false, previousTabID: nil)
        } else {
            tab = newTab()
            internalReturn = InternalReturn(page: page, closesTab: true, previousTabID: origin)
        }
        install(page, in: tab)
        return tab
    }

    func dismissInternalPage(_ page: BrowserTab.InternalPage) {
        guard let tab = tabs.first(where: { $0.internalPage == page }) else { return }
        let origin = internalReturn?.page == page ? internalReturn : nil
        internalReturn = nil

        if origin?.closesTab == true {
            close(tab)
            if let previous = origin?.previousTabID, tabs.contains(where: { $0.id == previous }) {
                activeTabID = previous
            }
            return
        }

        if let previous = origin?.previousTabID, tabs.contains(where: { $0.id == previous }) {
            activeTabID = previous
            return
        }

        tab.internalPage = nil
        tab.title = BrowserTab.placeholderTitle
        scheduleSave()
    }

    struct InternalReturn {
        let page: BrowserTab.InternalPage
        let closesTab: Bool
        let previousTabID: UUID?
    }

    private func install(_ page: BrowserTab.InternalPage, in tab: BrowserTab) {
        tab.internalPage = page
        tab.title = page.title
        tab.urlString = ""
        scheduleSave()
    }

    func contextSummary(mentionedTabIDs: [UUID] = []) -> String? {
        let split = activeSplit
        let onScreen = splitPanes ?? [activeTab].compactMap { $0 }
        var seen = Set(onScreen.map(\.id))
        let mentioned = mentionedTabIDs.compactMap { id -> BrowserTab? in
            guard let tab = tabsByID[id], seen.insert(id).inserted else { return nil }
            return tab
        }
        let pages = onScreen + mentioned
        guard !pages.isEmpty else { return nil }
        let lines = pages.enumerated().map { index, tab -> String in
            let host = URL(string: tab.urlString)?.displayHost ?? "blank"
            var marks: [String] = []
            if let place = split.flatMap({ Self.paneName(of: tab.id, in: $0) }) {
                marks.append("ON SCREEN, \(place)")
            }
            if tab.id == activeTab?.id {
                marks.append("ACTIVE")
            }
            if mentionedTabIDs.contains(tab.id) {
                marks.append("MENTIONED")
            }
            let marker = marks.isEmpty ? "" : " ← " + marks.joined(separator: ", ")
            return "\(index + 1). \(tab.title) (\(host))\(marker)"
        }
        var summary = "[Pages in context:\n" + lines.joined(separator: "\n")
        if let split {
            summary += """

                Split view: the \(split.count) pages marked ON SCREEN share the window, so the user is \
                looking at all of them at once. "these pages", "both of them" and "compare them" mean \
                exactly those, in that order - never ask which. Read one of them with readPage's page \
                argument; switchTab moves the active pane without hiding any of them.
                """
        }
        if !mentionedTabIDs.isEmpty {
            summary += """

                The user attached the tabs marked MENTIONED to this request. Read one with readPage's \
                page argument (its title or host) without switching to it; the request is about them.
                """
        }
        return summary + "]"
    }

    private nonisolated static func paneName(of tabID: UUID, in split: TabSplit) -> String? {
        guard let index = split.tabs.firstIndex(of: tabID) else { return nil }
        let place = "pane \(index + 1) of \(split.count)"
        if split.count == 2 {
            switch split.axis {
            case .sideBySide:
                return index == 0 ? "left" : "right"
            case .stacked:
                return index == 0 ? "top" : "bottom"
            case nil:
                return place
            }
        }
        switch split.lineAxis {
        case .sideBySide:
            return "\(place) from the left"
        case .stacked:
            return "\(place) from the top"
        case nil:
            return place
        }
    }

    // MARK: - Address input

    static func looksLikeLocation(_ text: String) -> Bool {
        if text.contains("://") {
            return true
        }
        return text.contains(".") && !text.contains(" ")
    }

    func handleAddressInput(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let tab = ensureActiveTab()

        if text.contains("://"), let url = URL(string: text) {
            tab.load(url)
        } else if Self.looksLikeLocation(text), let url = URL(string: "https://\(text)") {
            tab.load(url)
        } else {
            tab.load(SearchURLBuilder.searchURL(for: text))
        }
    }
}
