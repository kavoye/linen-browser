// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Observation
import SwiftUI

enum SidebarDestination: Hashable {
    case tab(UUID)

    static func resolve(activeTabID: UUID?) -> SidebarDestination? {
        activeTabID.map(SidebarDestination.tab)
    }
}

@MainActor
@Observable
final class SidebarSelection {
    private(set) var items: Set<SidebarItem> = []
    private(set) var anchor: SidebarItem?
    private(set) var ownsKeyboard = false

    var isEmpty: Bool {
        items.isEmpty
    }
    var count: Int {
        items.count
    }

    func contains(_ item: SidebarItem) -> Bool {
        items.contains(item)
    }

    func select(_ item: SidebarItem) {
        items = [item]
        anchor = item
    }

    func hold(_ active: SidebarItem?) {
        guard items.isEmpty, let active else { return }
        items = [active]
        if anchor == nil {
            anchor = active
        }
    }

    func toggle(_ item: SidebarItem) {
        if items.contains(item) {
            items.remove(item)
        } else {
            items.insert(item)
        }
        anchor = item
        ownsKeyboard = true
    }

    func anchor(on item: SidebarItem) {
        items = []
        anchor = item
    }

    func dropMarks() {
        guard !items.isEmpty || ownsKeyboard else { return }
        items = []
        ownsKeyboard = false
    }

    func takeKeyboard() {
        items = []
        anchor = nil
        ownsKeyboard = true
    }

    func extend(to item: SidebarItem, in tree: SidebarTree, isExpanded: @escaping (UUID) -> Bool) {
        guard let anchor, anchor != item else {
            select(item)
            return
        }
        items.formUnion(tree.range(from: anchor, to: item, isExpanded: isExpanded))
        ownsKeyboard = true
    }

    func selectAll(in tree: SidebarTree, isExpanded: @escaping (UUID) -> Bool) {
        let rows = tree.visibleRows(isExpanded: isExpanded)
        items = Set(rows)
        anchor = rows.first
        ownsKeyboard = true
    }

    func clear() {
        guard !items.isEmpty || anchor != nil || ownsKeyboard else { return }
        items = []
        anchor = nil
        ownsKeyboard = false
    }

    func prune(to live: Set<SidebarItem>) {
        guard !items.isSubset(of: live) else { return }
        items.formIntersection(live)
        if let anchor, !live.contains(anchor) {
            self.anchor = nil
        }
    }

    func carried(startingOn item: SidebarItem, in tree: SidebarTree) -> [SidebarItem] {
        guard items.contains(item) else {
            anchor(on: item)
            return [item]
        }
        return tree.normalized(items)
    }
}

@MainActor
@Observable
final class SidebarNewFolderDrop {
    @ObservationIgnored var frame: CGRect = .zero
    var isArmed = false
}
