// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension AppCoordinator {
    // MARK: - Split view

    var isSplit: Bool {
        browser.activeSplit != nil
    }

    func splitActiveTab(axis: SplitAxis) {
        guard let current = browser.activeTab else { return }
        let opened = browser.newTab(activate: false)
        if browser.splits.contains(current.id) {
            browser.insertIntoSplit(opened, beside: current, edge: axis == .sideBySide ? .right : .bottom)
        } else {
            browser.split(current, with: opened, axis: axis)
        }
        browser.activate(opened)
    }

    func split(_ anchor: BrowserTab, with tab: BrowserTab, axis: SplitAxis, placingTabFirst: Bool = false) {
        guard anchor !== tab else { return }
        if placingTabFirst {
            browser.split(tab, with: anchor, axis: axis)
        } else {
            browser.split(anchor, with: tab, axis: axis)
        }
        browser.activate(tab)
    }

    func dropOnPage(_ tab: BrowserTab, onto anchorID: UUID?, zone: SplitDropZone) {
        guard !isShowingSettings, zone != .none else { return }
        let anchor = anchorID.flatMap { browser.tab(id: $0) } ?? browser.activeTab
        guard let anchor, anchor !== tab else { return }

        if browser.splits.contains(anchor.id) {
            browser.insertIntoSplit(tab, beside: anchor, edge: zone)
        } else if let axis = zone.axis {
            split(anchor, with: tab, axis: axis, placingTabFirst: zone.placesDroppedTabFirst)
            return
        } else {
            openTab(tab)
            return
        }
        browser.activate(tab)
    }

    func beginPaneDrag(_ tab: BrowserTab) {
        browser.paneInAir = tab.id
    }

    func movePane(_ tab: BrowserTab, onto anchorID: UUID?, zone: SplitDropZone, stayingOnThePage: Bool) {
        browser.paneInAir = nil
        guard let split = browser.activeSplit, split.contains(tab.id) else { return }

        guard stayingOnThePage else {
            let survivor = browser.splitOthers(of: tab).first
            browser.removeFromSplit(tab)
            if let survivor {
                browser.activate(survivor)
            }
            return
        }

        guard zone != .none,
              let anchor = anchorID.flatMap({ browser.tab(id: $0) }),
              anchor !== tab
        else { return }
        browser.moveSplitPane(tab, beside: anchor, edge: zone)
    }

    func swapSplitPanes() {
        guard let tab = browser.activeTab, browser.isVisibleInSplit(tab) else { return }
        browser.swapSplitRow(containing: tab)
    }

    func toggleSplitAxis() {
        setSplitAxis(browser.activeSplit?.axis == .stacked ? .sideBySide : .stacked)
    }

    func setSplitAxis(_ axis: SplitAxis) {
        guard let tab = browser.activeTab, browser.isVisibleInSplit(tab) else { return }
        browser.setSplitAxis(axis, containing: tab)
    }

    func focusOtherPane() {
        guard let tab = browser.activeTab, let split = browser.activeSplit,
              let at = split.tabs.firstIndex(of: tab.id)
        else { return }
        let next = split.tabs[(at + 1) % split.tabs.count]
        guard let pane = browser.tab(id: next) else { return }
        browser.activate(pane)
    }

    func exitSplit() {
        guard let tab = browser.activeTab else { return }
        browser.dissolveSplit(containing: tab)
    }

    func closeOtherPanes() {
        guard let tab = browser.activeTab, browser.isVisibleInSplit(tab) else { return }
        for pane in browser.splitOthers(of: tab) {
            browser.close(pane)
        }
    }
}
