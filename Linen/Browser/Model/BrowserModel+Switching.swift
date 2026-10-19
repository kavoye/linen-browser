// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct ShiftStep {
    private var isPending = false

    mutating func shiftDown(whileSwitching: Bool) {
        isPending = whileSwitching
    }

    mutating func shiftUp() -> Bool {
        defer { isPending = false }
        return isPending
    }

    mutating func cancel() {
        isPending = false
    }
}

extension BrowserModel {
    var isSwitchingTabs: Bool {
        switcherRecency != nil
    }

    var switcherTabs: [BrowserTab] {
        guard let switcherRecency else { return [] }
        var order = switcherRecency.compactMap { tabsByID[$0] }
        if let active = activeTab {
            order.removeAll { $0 === active }
            order.insert(active, at: 0)
        }
        let listed = Set(order.map(\.id))
        return order + tabs.filter { !listed.contains($0.id) }
    }

    func switchTab(forward: Bool) {
        guard tabs.count > 1 else { return }
        beginTabSwitching()
        moveSwitcherSelection(forward: forward)
    }

    private func moveSwitcherSelection(forward: Bool) {
        guard isSwitchingTabs else { return }
        let order = switcherTabs
        let current = order.firstIndex { $0.id == switcherSelection } ?? 0
        let next = (current + (forward ? 1 : -1) + order.count) % order.count
        switcherSelection = order[next].id
    }

    func endTabSwitching() {
        guard isSwitchingTabs else { return }
        let chosen = switcherSelection.flatMap { tabsByID[$0] }
        cancelTabSwitching()
        if let chosen, chosen !== activeTab {
            activate(chosen)
        }
    }

    func endTabSwitching(choosing id: UUID) {
        guard isSwitchingTabs else { return }
        switcherSelection = id
        endTabSwitching()
    }

    func cancelTabSwitching() {
        switcherRecency = nil
        switcherSelection = nil
    }

    func switcherTabClosed(at index: Int) {
        let order = switcherTabs
        guard !order.isEmpty else {
            cancelTabSwitching()
            return
        }
        if switcherSelection.flatMap({ tabsByID[$0] }) == nil {
            switcherSelection = order[min(index, order.count - 1)].id
        }
    }

    private func beginTabSwitching() {
        guard !isSwitchingTabs else { return }
        switcherRecency = recentlyActive
        activeTab?.refreshPreview()
    }
}
