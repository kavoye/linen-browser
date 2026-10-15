// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension BrowserModel {
    // MARK: - Spaces

    func isInCurrentSpace(_ tab: BrowserTab) -> Bool {
        currentSpaceID == nil || tab.spaceID == currentSpaceID
    }

    var currentSpaceTabs: [BrowserTab] {
        tabs.filter(isInCurrentSpace)
    }

    func rootItems(inSpace id: UUID) -> [SidebarItem] {
        spaceRoots[id] ?? []
    }

    func lastActiveTab(inSpace id: UUID) -> BrowserTab? {
        recentlyActive.lazy.compactMap { self.tabsByID[$0] }.first { $0.spaceID == id }
            ?? tabs.first { $0.spaceID == id }
    }

    func spaceID(ofItem item: SidebarItem) -> UUID? {
        switch item {
        case .tab(let id):
            tabsByID[id]?.spaceID
        case .folder(let id):
            foldersByID[id]?.spaceID
        }
    }

    func isInCurrentSpace(_ item: SidebarItem) -> Bool {
        currentSpaceID == nil || spaceID(ofItem: item) == currentSpaceID
    }

    func settleSpaces(in tree: SidebarTree) {
        guard let currentSpaceID else { return }
        for item in tree.root {
            let space = spaceID(ofItem: item).flatMap(knownSpace) ?? currentSpaceID
            assignSpace(space, to: item)
            guard case .folder(let id) = item else { continue }
            for held in tree.descendants(ofFolder: id) {
                assignSpace(space, to: held)
            }
        }
    }

    private func knownSpace(_ id: UUID) -> UUID? {
        knownSpaceIDs.isEmpty || knownSpaceIDs.contains(id) ? id : nil
    }

    private func assignSpace(_ space: UUID, to item: SidebarItem) {
        switch item {
        case .tab(let id):
            if let tab = tabsByID[id], tab.spaceID != space {
                tab.spaceID = space
            }
        case .folder(let id):
            if let folder = foldersByID[id], folder.spaceID != space {
                folder.spaceID = space
            }
        }
    }

    func move(_ items: [SidebarItem], toSpace id: UUID) {
        guard currentSpaceID == nil || id != currentSpaceID else { return }
        let tree = reconciledTree()
        let moved = tree.normalized(withSplitMembers(items))
        guard !moved.isEmpty else { return }
        let carried = tree.expanded(Set(moved))
        let wasActive = activeTabID.map { carried.contains(.tab($0)) } ?? false
        let kept = moved.filter { isKept($0) }
        let loose = moved.filter { !isKept($0) }
        for item in carried {
            assignSpace(id, to: item)
        }
        let boundary = tree.root.first { item in
            !carried.contains(item) && spaceID(ofItem: item) == id && !isKept(item)
        }
        place(kept + loose, in: nil, before: boundary)
        sidebarDidChange()
        if wasActive {
            activeTabID = (currentSpaceID.flatMap(lastActiveTab(inSpace:)) ?? currentSpaceTabs.first)?.id
            if activeTabID == nil {
                newTab()
            }
        }
        scheduleSave()
    }

    func closeSpace(_ id: UUID) {
        for tab in tabs.reversed() where tab.spaceID == id {
            close(tab, recordForReopening: false)
        }
        folders.removeAll { $0.spaceID == id }
        sidebarDidChange()
        scheduleSave()
    }
}
