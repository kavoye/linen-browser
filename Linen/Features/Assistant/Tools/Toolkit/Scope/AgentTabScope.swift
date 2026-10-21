// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

@MainActor
final class AgentTabScope {
    private let browser: BrowserModel
    private(set) var task: AgentTaskContext?
    private var seededTabIDs: Set<UUID> = []
    private(set) var openedTabIDs: Set<UUID> = []

    init(browser: BrowserModel) {
        self.browser = browser
    }

    func begin(_ task: AgentTaskContext) {
        self.task = task
        seededTabIDs = Set(onScreenTabs.map(\.id))
        openedTabIDs = []
    }

    func finish(_ completed: AgentTaskContext) -> Set<UUID>? {
        guard task?.id == completed.id else { return nil }
        task = nil
        return openedTabIDs
    }

    func continueTask(_ continued: AgentTaskContext) {
        task = continued
    }

    func followActiveTab() -> AgentTaskContext? {
        guard let task, let tab = browser.activeTab, !tab.isPrivate else { return nil }
        let anchor = browser.anchorID(of: tab.id)
        guard anchor != task.anchorID, !openedTabIDs.contains(tab.id) else { return task }
        let moved = AgentTaskContext(id: task.id, tabID: tab.id, anchorID: anchor, isContinuation: true, driver: task.driver)
        self.task = moved
        seededTabIDs.formUnion(onScreenTabs.map(\.id))
        return moved
    }

    func noteOpened(_ tab: BrowserTab) {
        openedTabIDs.insert(tab.id)
    }

    var onScreenTabs: [BrowserTab] {
        guard let active = browser.activeTab else { return [] }
        return browser.splitPanes ?? [active]
    }

    var mentionedTabs: [BrowserTab] {
        (task?.mentionedTabIDs ?? []).compactMap { id in
            browser.tabs.first { $0.id == id }
        }
    }

    var visibleTaskTab: BrowserTab? {
        guard let tab = browser.activeTab, belongsToTask(tab) else { return nil }
        return tab
    }

    func belongsToTask(_ tab: BrowserTab) -> Bool {
        guard let task else { return true }
        return browser.anchorID(of: tab.id) == task.anchorID || openedTabIDs.contains(tab.id)
    }

    var contextTabIDs: Set<UUID> {
        guard task != nil else { return Set(onScreenTabs.map(\.id)) }
        return seededTabIDs
            .union(openedTabIDs)
            .union(mentionedTabs.map(\.id))
    }

    func contextTab(matching reference: String) -> BrowserTab? {
        let needle = reference.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        let allowed = contextTabIDs
        let matches = browser.tabs.filter {
            allowed.contains($0.id)
                && ($0.id.uuidString.lowercased() == needle || $0.title.lowercased().contains(needle) || $0.urlString.lowercased().contains(needle))
        }
        return matches.count == 1 ? matches.first : nil
    }

    func missingContextTabOutput() -> String {
        guard !browser.tabs.isEmpty else { return "There are no tabs open." }
        let allowed = contextTabIDs
        let titles = browser.tabs.filter { allowed.contains($0.id) }.map(\.title)
        guard !titles.isEmpty else { return "No tab belongs to this conversation yet." }
        return "No tab in this conversation matches. Its tabs: \(titles.joined(separator: " | "))"
    }

    func onScreenTab(named reference: String) -> BrowserTab? {
        let panes = onScreenTabs
        let needle = reference.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if panes.count > 1,
           let split = browser.activeSplit,
           let index = Self.paneIndex(named: needle, axis: split.lineAxis, count: panes.count) {
            return panes.indices.contains(index) ? panes[index] : nil
        }
        return panes.first {
            $0.id.uuidString.lowercased() == needle || $0.title.lowercased().contains(needle) || $0.urlString.lowercased().contains(needle)
        }
    }

    func onScreenTab(for webView: WKWebView) -> BrowserTab? {
        onScreenTabs.first { $0.webView === webView }
    }

    func mentionedTab(for webView: WKWebView) -> BrowserTab? {
        mentionedTabs.first { $0.webView === webView }
    }

    func pageIdentifier(for view: WKWebView) -> String {
        browser.tabs.first { $0.isMaterialised && $0.webView === view }?.id.uuidString ?? ""
    }

    func pageSurface(named reference: String) -> WKWebView? {
        if reference.isEmpty || reference == "research" {
            return browser.activeTab?.webView
        }
        let needle = reference.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let candidates = onScreenTabs + mentionedTabs.filter { mentioned in !onScreenTabs.contains { $0.id == mentioned.id } }
        if let exact = candidates.first(where: { $0.id.uuidString.lowercased() == needle }) {
            exact.realizeDeferredSession()
            return exact.webView
        }
        if ["left", "right", "top", "bottom", "first", "second", "third", "fourth", "1", "2", "3", "4"].contains(needle),
           let positional = onScreenTab(named: needle) { return positional.webView }
        let label = AgentToolkit.contextLabel(needle)
        if label.isActive, let active = browser.activeTab {
            return active.webView
        }
        let matches = candidates.filter { tab in
            tab.title.lowercased().contains(label.title) || tab.urlString.lowercased().contains(label.title)
                || (label.host.map { tab.urlString.lowercased().contains($0) } ?? false)
        }
        if matches.count == 1, let found = matches.first {
            found.realizeDeferredSession()
            return found.webView
        }
        return nil
    }

    private nonisolated static func paneIndex(named needle: String, axis: SplitAxis?, count: Int) -> Int? {
        let ordinals = ["first", "second", "third", "fourth"]
        if let index = ordinals.firstIndex(of: needle), index < count {
            return index
        }
        if let number = Int(needle), (1...count).contains(number) {
            return number - 1
        }
        switch (needle, axis) {
        case ("left", .sideBySide), ("top", .stacked):
            return 0
        case ("right", .sideBySide), ("bottom", .stacked):
            return count - 1
        default:
            return nil
        }
    }
}
