// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

enum ModifierTap {
    static let window: TimeInterval = 0.12

    static func isTap(downAt: TimeInterval?, now: TimeInterval) -> Bool {
        guard let downAt else { return false }
        return now - downAt < window
    }
}

extension BrowserModel {
    var previouslyActiveTabID: UUID? {
        recentlyActive.first { $0 != activeTabID && tabsByID[$0] != nil }
    }

    var isSwitchingTabs: Bool {
        switcherRecency != nil
    }

    func switchTab(forward: Bool, asTap: Bool = false) {
        guard tabs.count > 1 else { return }
        let isFirstStep = !isSwitchingTabs
        if isFirstStep {
            switcherRecency = recentlyActive
        }
        if isFirstStep, forward, asTap,
           let previous = previouslyActiveTabID, let tab = tabsByID[previous] {
            activate(tab)
            return
        }
        cycleTab(forward: forward)
    }

    func endTabSwitching() {
        guard let recency = switcherRecency else { return }
        switcherRecency = nil
        guard let landed = activeTabID else { return }
        var restored = recency
        restored.removeAll { $0 == landed }
        restored.insert(landed, at: 0)
        recentlyActive = restored
    }
}
