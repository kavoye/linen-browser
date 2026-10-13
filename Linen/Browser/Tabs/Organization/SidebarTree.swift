// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct SidebarTree: Equatable, Sendable {
    private(set) var root: [SidebarItem] = []
    private(set) var children: [UUID: [SidebarItem]] = [:]

    init(root: [SidebarItem] = [], children: [UUID: [SidebarItem]] = [:]) {
        self.root = root
        self.children = children.filter { !$0.value.isEmpty }
    }

    func rows(in parent: UUID?) -> [SidebarItem] {
        guard let parent else { return root }
        return children[parent] ?? []
    }

    private mutating func setRows(_ rows: [SidebarItem], in parent: UUID?) {
        guard let parent else {
            root = rows
            return
        }
        if rows.isEmpty {
            children.removeValue(forKey: parent)
        } else {
            children[parent] = rows
        }
    }

    func parents() -> [SidebarItem: UUID] {
        var map: [SidebarItem: UUID] = [:]
        for (folderID, rows) in children {
            for row in rows {
                map[row] = folderID
            }
        }
        return map
    }

    func parent(of item: SidebarItem) -> UUID? {
        children.first { $0.value.contains(item) }?.key
    }

    func successor(of item: SidebarItem) -> SidebarItem? {
        let siblings = rows(in: parent(of: item))
        guard let index = siblings.firstIndex(of: item), index + 1 < siblings.endIndex else { return nil }
        return siblings[index + 1]
    }

    func depth(of item: SidebarItem) -> Int {
        let parents = parents()
        var depth = 0
        var walked = Set<UUID>()
        var current = parents[item]
        while let id = current, walked.insert(id).inserted {
            depth += 1
            current = parents[.folder(id)]
        }
        return depth
    }

    func walk() -> [SidebarItem] {
        gather(descend: { _ in true })
    }

    func visibleRows(isExpanded: (UUID) -> Bool) -> [SidebarItem] {
        gather(descend: isExpanded)
    }

    func flattenedTabs(known: Set<UUID>) -> [UUID] {
        walk().compactMap { item in
            guard case .tab(let id) = item, known.contains(id) else { return nil }
            return id
        }
    }

    func descendants(ofFolder id: UUID) -> Set<SidebarItem> {
        var found: [SidebarItem] = []
        var seen: Set<SidebarItem> = []
        collect(id, into: &found, seen: &seen, descend: { _ in true })
        return Set(found)
    }

    private func gather(descend: (UUID) -> Bool) -> [SidebarItem] {
        var found: [SidebarItem] = []
        var seen: Set<SidebarItem> = []
        collect(nil, into: &found, seen: &seen, descend: descend)
        return found
    }

    private func collect(
        _ parent: UUID?,
        into found: inout [SidebarItem],
        seen: inout Set<SidebarItem>,
        descend: (UUID) -> Bool
    ) {
        for item in rows(in: parent) where seen.insert(item).inserted {
            found.append(item)
            guard case .folder(let id) = item, descend(id) else { continue }
            collect(id, into: &found, seen: &seen, descend: descend)
        }
    }

    static func reconcile(stored: SidebarTree, folders: [UUID], tabs: [UUID]) -> SidebarTree {
        let liveFolders = Set(folders)
        let liveTabs = Set(tabs)
        func exists(_ item: SidebarItem) -> Bool {
            switch item {
            case .folder(let id):
                liveFolders.contains(id)
            case .tab(let id):
                liveTabs.contains(id)
            }
        }

        var placed: Set<SidebarItem> = []
        var next = SidebarTree()

        func take(_ parent: UUID?) {
            var kept = next.rows(in: parent)
            for item in stored.rows(in: parent) where exists(item) && placed.insert(item).inserted {
                kept.append(item)
            }
            next.setRows(kept, in: parent)
            for case .folder(let id) in kept {
                take(id)
            }
        }
        take(nil)

        for item in folders.map(SidebarItem.folder) + tabs.map(SidebarItem.tab)
        where placed.insert(item).inserted {
            next.setRows(next.root + [item], in: nil)
            if case .folder(let id) = item {
                take(id)
            }
        }
        return next
    }

    func moving(_ items: [SidebarItem], into parent: UUID?, before target: SidebarItem?) -> SidebarTree? {
        guard !items.isEmpty else { return nil }
        if let target, items.contains(target) {
            return nil
        }
        if let parent, !canHold(parent, items) {
            return nil
        }

        var next = self
        let moved = Set(items)
        next.setRows(next.root.filter { !moved.contains($0) }, in: nil)
        for (folderID, rows) in next.children {
            next.setRows(rows.filter { !moved.contains($0) }, in: folderID)
        }

        var destination = next.rows(in: parent)
        let at = target.flatMap { destination.firstIndex(of: $0) } ?? destination.endIndex
        destination.insert(contentsOf: items, at: at)
        next.setRows(destination, in: parent)
        return next == self ? nil : next
    }

    func canHold(_ folder: UUID, _ items: [SidebarItem]) -> Bool {
        let destination = SidebarItem.folder(folder)
        for case .folder(let id) in items {
            if id == folder {
                return false
            }
            if descendants(ofFolder: id).contains(destination) {
                return false
            }
        }
        return true
    }

    func inserting(_ item: SidebarItem, after anchor: SidebarItem) -> SidebarTree {
        guard item != anchor else { return self }
        let home = parent(of: anchor)
        return moving([item], into: home, before: successor(of: anchor)) ?? self
    }

    func removing(_ items: Set<SidebarItem>) -> SidebarTree {
        guard !items.isEmpty else { return self }
        var next = self
        next.setRows(next.root.filter { !items.contains($0) }, in: nil)
        for (folderID, rows) in next.children {
            next.setRows(rows.filter { !items.contains($0) }, in: folderID)
        }
        for case .folder(let id) in items {
            next.children.removeValue(forKey: id)
        }
        return next
    }

    func dissolving(_ folder: UUID) -> SidebarTree {
        let item = SidebarItem.folder(folder)
        let home = parent(of: item)
        let held = rows(in: folder)
        var next = self
        next.children.removeValue(forKey: folder)
        var siblings = next.rows(in: home)
        let spot = siblings.firstIndex(of: item) ?? siblings.endIndex
        siblings.replaceSubrange(spot..<min(spot + 1, siblings.endIndex), with: held)
        next.setRows(siblings, in: home)
        return next
    }

    func normalized(_ items: [SidebarItem]) -> [SidebarItem] {
        guard !items.isEmpty else { return [] }
        var listedFolders: Set<UUID> = []
        for case .folder(let id) in items {
            listedFolders.insert(id)
        }
        let parents = parents()

        func isHeldByAnother(_ item: SidebarItem) -> Bool {
            var walked = Set<UUID>()
            var current = parents[item]
            while let id = current, walked.insert(id).inserted {
                if listedFolders.contains(id) {
                    return true
                }
                current = parents[.folder(id)]
            }
            return false
        }

        var seen: Set<SidebarItem> = []
        return items.filter { seen.insert($0).inserted && !isHeldByAnother($0) }
    }

    func normalized(_ selection: Set<SidebarItem>) -> [SidebarItem] {
        normalized(walk().filter { selection.contains($0) })
    }

    func expanded(_ selection: Set<SidebarItem>) -> Set<SidebarItem> {
        var result = selection
        for case .folder(let id) in selection {
            result.formUnion(descendants(ofFolder: id))
        }
        return result
    }

    func range(from anchor: SidebarItem, to target: SidebarItem, isExpanded: (UUID) -> Bool) -> [SidebarItem] {
        let rows = visibleRows(isExpanded: isExpanded)
        guard let start = rows.firstIndex(of: anchor), let end = rows.firstIndex(of: target) else {
            return [target]
        }
        return Array(rows[min(start, end)...max(start, end)])
    }
}
