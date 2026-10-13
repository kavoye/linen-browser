// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation

extension BrowserModel {
    /// Transfer the existing page without navigation or a second web view.
    @discardableResult
    func adoptTab(_ tab: BrowserTab, from source: BrowserModel) -> Bool {
        guard source !== self, source.context === context,
              source.sessionClosedAt == nil, sessionClosedAt == nil,
              source.opensPrivately == opensPrivately,
              (source.database.writer as AnyObject) === (database.writer as AnyObject),
              let oldIndex = source.tabs.firstIndex(where: { $0 === tab }),
              !tabs.contains(where: { $0.id == tab.id }), !tab.isClosed else { return false }

        source.onTabWillTransferOut?(tab)
        let survivor = source.splits.others(of: tab.id).first.flatMap { source.tabsByID[$0] }
            ?? source.tabs.dropFirst(oldIndex + 1).first
            ?? source.tabs.prefix(oldIndex).last
        let wasActive = source.activeTabID == tab.id
        let visitID = source.lastVisitID.removeValue(forKey: tab.id)
        source.splits = source.splits.removing(tab.id)
        source.storedTree = source.reconciledTree().removing([.tab(tab.id)])
        source.tabs.remove(at: oldIndex)
        source.recentlyActive.removeAll { $0 == tab.id }
        source.cancelTabSwitching()
        if source.paneInAir == tab.id {
            source.paneInAir = nil
        }
        source.sidebarDidChange()
        if wasActive {
            source.activeTabID = survivor?.id
        }

        if tab.isMaterialised {
            AutofillSuggestions.shared.dismiss(in: tab.webView)
            tab.webView.removeFromSuperview()
        }
        bindCallbacks(to: tab)
        insert(tab, after: nil)
        lastVisitID[tab.id] = visitID
        writtenStateGeneration[tab.id] = nil
        source.onTabTransferredOut?(tab, oldIndex)
        onTabTransferredIn?(tab, source, oldIndex)
        activeTabID = tab.id
        saveTransferredSession(from: source)
        return true
    }
}
