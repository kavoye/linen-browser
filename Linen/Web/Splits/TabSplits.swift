// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import Foundation

nonisolated enum SplitAxis: String, Codable, Sendable, CaseIterable {
    case sideBySide
    case stacked

    var opposite: SplitAxis {
        self == .sideBySide ? .stacked : .sideBySide
    }
}

nonisolated struct SplitNode: Equatable, Sendable, Codable {
    nonisolated enum Content: Equatable, Sendable, Codable {
        case page(UUID)
        case group(axis: SplitAxis, children: [SplitNode])
    }

    var content: Content
    var share: CGFloat

    init(_ content: Content, share: CGFloat = 1) {
        self.content = content
        self.share = share
    }

    static func page(_ id: UUID, share: CGFloat = 1) -> SplitNode {
        SplitNode(.page(id), share: share)
    }

    static func group(_ axis: SplitAxis, _ children: [SplitNode], share: CGFloat = 1) -> SplitNode {
        SplitNode(.group(axis: axis, children: children), share: share)
    }

    var pageID: UUID? {
        guard case .page(let id) = content else { return nil }
        return id
    }

    var axis: SplitAxis? {
        guard case .group(let axis, _) = content else { return nil }
        return axis
    }

    var children: [SplitNode] {
        get {
            guard case .group(_, let children) = content else { return [] }
            return children
        }
        set {
            guard case .group(let axis, _) = content else { return }
            content = .group(axis: axis, children: newValue)
        }
    }

    var pages: [UUID] {
        switch content {
        case .page(let id):
            [id]
        case .group(_, let children):
            children.flatMap(\.pages)
        }
    }

    var count: Int {
        switch content {
        case .page:
            1
        case .group(_, let children):
            children.reduce(0) { $0 + $1.count }
        }
    }

    func path(of id: UUID) -> [Int]? {
        if pageID == id {
            return []
        }
        for (index, child) in children.enumerated() {
            if let rest = child.path(of: id) {
                return [index] + rest
            }
        }
        return nil
    }

    subscript(path: [Int]) -> SplitNode? {
        get {
            guard let first = path.first else { return self }
            guard children.indices.contains(first) else { return nil }
            return children[first][Array(path.dropFirst())]
        }
        set {
            guard let newValue else { return }
            guard let first = path.first else {
                self = newValue
                return
            }
            guard children.indices.contains(first) else { return }
            children[first][Array(path.dropFirst())] = newValue
        }
    }

    func touchesTop(_ id: UUID) -> Bool {
        guard let path = path(of: id) else { return false }
        var node = self
        for step in path {
            if node.axis == .stacked, step != 0 {
                return false
            }
            node = node.children[step]
        }
        return true
    }

    // MARK: - Shape

    func normalized() -> SplitNode? {
        guard case .group(let axis, let children) = content else { return self }

        var flattened: [SplitNode] = []
        for child in children.compactMap({ $0.normalized() }) {
            if child.axis == axis {
                let total = child.children.reduce(0) { $0 + $1.share }
                guard total > 0 else { continue }
                for var grandchild in child.children {
                    grandchild.share = child.share * (grandchild.share / total)
                    flattened.append(grandchild)
                }
            } else {
                flattened.append(child)
            }
        }

        guard !flattened.isEmpty else { return nil }
        if flattened.count == 1 {
            var only = flattened[0]
            only.share = share
            return only
        }
        return SplitNode.group(axis, Self.balanced(flattened), share: share)
    }

    static func balanced(_ nodes: [SplitNode]) -> [SplitNode] {
        let total = nodes.reduce(0) { $0 + $1.share }
        guard total > 0 else {
            let even = 1 / CGFloat(nodes.count)
            return nodes.map { SplitNode($0.content, share: even) }
        }
        return nodes.map { SplitNode($0.content, share: $0.share / total) }
    }

    var stackedLineCount: Int {
        switch content {
        case .page:
            1
        case .group(let axis, let children):
            axis == .stacked
                ? children.reduce(0) { $0 + $1.stackedLineCount }
                : children.map(\.stackedLineCount).max() ?? 1
        }
    }

    func evenlyDivided() -> SplitNode {
        switch content {
        case .page:
            return self
        case .group(let axis, let children):
            let even = 1 / CGFloat(children.count)
            return .group(axis, children.map { child in
                var divided = child.evenlyDivided()
                divided.share = even
                return divided
            }, share: share)
        }
    }

    func pruned(to live: Set<UUID>, seen: inout Set<UUID>) -> SplitNode? {
        switch content {
        case .page(let id):
            guard live.contains(id), seen.insert(id).inserted else { return nil }
            return self
        case .group(let axis, let children):
            let kept = children.compactMap { $0.pruned(to: live, seen: &seen) }
            guard !kept.isEmpty else { return nil }
            return SplitNode.group(axis, kept, share: share).normalized()
        }
    }
}

nonisolated struct TabSplit: Equatable, Sendable, Codable {
    private(set) var root: SplitNode

    static let maxPanes = 4

    static let shareRange: ClosedRange<CGFloat> = 0.15...0.85

    static let minimumPaneLength: CGFloat = 240

    init?(root: SplitNode) {
        guard let normalized = root.normalized(), normalized.count >= 2, normalized.axis != nil else {
            return nil
        }
        self.root = normalized
    }

    init(_ first: UUID, _ second: UUID, axis: SplitAxis) {
        root = .group(axis, [.page(first, share: 0.5), .page(second, share: 0.5)])
    }

    var tabs: [UUID] {
        root.pages
    }

    var count: Int {
        root.count
    }

    var isFull: Bool {
        count >= Self.maxPanes
    }

    var leader: UUID? {
        tabs.first
    }

    func contains(_ id: UUID) -> Bool {
        root.path(of: id) != nil
    }

    func path(of id: UUID) -> [Int]? {
        root.path(of: id)
    }

    func isUnderTopBar(_ id: UUID) -> Bool {
        root.touchesTop(id)
    }

    var axis: SplitAxis? {
        guard count == 2 else { return nil }
        return root.axis
    }

    var lineAxis: SplitAxis? {
        guard root.children.allSatisfy({ $0.pageID != nil }) else { return nil }
        return root.axis
    }

    func line(of id: UUID) -> (path: [Int], index: Int)? {
        guard let path = root.path(of: id), let index = path.last else { return nil }
        return (Array(path.dropLast()), index)
    }

    func sibling(of id: UUID) -> UUID? {
        guard let (path, index) = line(of: id),
              let group = root[path], group.children.count == 2
        else { return nil }
        return group.children[1 - index].pageID
    }

    var sidebarShape: TabSplit {
        TabSplit(root: root.evenlyDivided()) ?? self
    }

    var sidebarLineCount: Int {
        root.stackedLineCount
    }
}

nonisolated struct TabSplits: Equatable, Sendable {
    private(set) var splits: [TabSplit] = []

    init(_ splits: [TabSplit] = []) {
        self.splits = splits.filter { $0.count >= 2 }
    }

    var isEmpty: Bool {
        splits.isEmpty
    }

    func split(containing id: UUID) -> TabSplit? {
        splits.first { $0.contains(id) }
    }

    func contains(_ id: UUID) -> Bool {
        split(containing: id) != nil
    }

    func others(of id: UUID) -> [UUID] {
        split(containing: id)?.tabs.filter { $0 != id } ?? []
    }

    var pairedTabs: Set<UUID> {
        Set(splits.flatMap(\.tabs))
    }

    var followerTabs: Set<UUID> {
        Set(splits.flatMap { $0.tabs.dropFirst() })
    }

    func isFollower(_ id: UUID) -> Bool {
        followerTabs.contains(id)
    }

    func splitLed(by id: UUID) -> TabSplit? {
        splits.first { $0.leader == id }
    }

    // MARK: - Building

    func splitting(_ anchor: UUID, with tab: UUID, axis: SplitAxis) -> TabSplits {
        guard anchor != tab else { return self }
        var next = removing(anchor).removing(tab)
        next.splits.append(TabSplit(anchor, tab, axis: axis))
        return next
    }

    func inserting(_ tab: UUID, beside anchor: UUID, edge: SplitDropZone) -> TabSplits {
        guard tab != anchor else { return self }
        switch edge {
        case .none:
            return self
        case .centre:
            return replacing(anchor, with: tab)
        case .left, .right, .top, .bottom:
            break
        }

        var next = removing(tab)
        guard let at = next.splits.firstIndex(where: { $0.contains(anchor) }) else {
            guard let axis = edge.axis, split(containing: anchor)?.contains(tab) == true else {
                return next
            }
            next.splits.append(
                edge.placesDroppedTabFirst
                    ? TabSplit(tab, anchor, axis: axis)
                    : TabSplit(anchor, tab, axis: axis)
            )
            return next
        }
        guard !next.splits[at].isFull else { return next.replacing(anchor, with: tab) }
        guard let path = next.splits[at].path(of: anchor), let index = path.last else { return next }

        let axis = edge.axis ?? .sideBySide
        let before = edge.placesDroppedTabFirst
        let parentPath = Array(path.dropLast())
        var root = next.splits[at].root
        guard var parent = root[parentPath] else { return next }
        let anchorNode = parent.children[index]

        if parent.axis == axis {
            var mine = anchorNode
            mine.share = anchorNode.share / 2
            let arriving = SplitNode.page(tab, share: anchorNode.share / 2)
            parent.children.replaceSubrange(
                index...index,
                with: before ? [arriving, mine] : [mine, arriving]
            )
        } else {
            var mine = anchorNode
            mine.share = 0.5
            let arriving = SplitNode.page(tab, share: 0.5)
            parent.children[index] = .group(
                axis,
                before ? [arriving, mine] : [mine, arriving],
                share: anchorNode.share
            )
        }
        root[parentPath] = parent

        guard let rebuilt = TabSplit(root: root) else { return next }
        next.splits[at] = rebuilt
        return next
    }

    func moving(_ tab: UUID, beside anchor: UUID, edge: SplitDropZone) -> TabSplits {
        guard tab != anchor, let before = split(containing: tab), before.contains(anchor) else {
            return self
        }
        if edge == .centre {
            return exchanging(tab, anchor)
        }
        return inserting(tab, beside: anchor, edge: edge)
    }

    func exchanging(_ one: UUID, _ other: UUID) -> TabSplits {
        guard let at = splits.firstIndex(where: { $0.contains(one) }), splits[at].contains(other) else {
            return self
        }
        var root = splits[at].root
        guard let here = root.path(of: one), let there = root.path(of: other) else { return self }
        root[here] = SplitNode(.page(other), share: root[here]?.share ?? 0.5)
        root[there] = SplitNode(.page(one), share: root[there]?.share ?? 0.5)
        guard let rebuilt = TabSplit(root: root) else { return self }
        var next = self
        next.splits[at] = rebuilt
        return next
    }

    func replacing(_ replaced: UUID, with tab: UUID) -> TabSplits {
        guard replaced != tab else { return self }
        var next = removing(tab)
        guard let at = next.splits.firstIndex(where: { $0.contains(replaced) }) else { return next }
        var root = next.splits[at].root
        guard let path = root.path(of: replaced) else { return next }
        root[path] = SplitNode(.page(tab), share: root[path]?.share ?? 0.5)
        guard let rebuilt = TabSplit(root: root) else { return next }
        next.splits[at] = rebuilt
        return next
    }

    func removing(_ id: UUID) -> TabSplits {
        guard let at = splits.firstIndex(where: { $0.contains(id) }) else { return self }
        var next = self
        var root = splits[at].root
        guard let path = root.path(of: id), let index = path.last else { return self }
        let parentPath = Array(path.dropLast())
        guard var parent = root[parentPath] else { return self }
        parent.children.remove(at: index)
        parent.children = SplitNode.balanced(parent.children)
        root[parentPath] = parent

        if let rebuilt = TabSplit(root: root) {
            next.splits[at] = rebuilt
        } else {
            next.splits.remove(at: at)
        }
        return next
    }

    func dissolving(containing id: UUID) -> TabSplits {
        var next = self
        next.splits.removeAll { $0.contains(id) }
        return next
    }

    // MARK: - Rearranging

    func setting(axis: SplitAxis, containing id: UUID) -> TabSplits {
        guard let at = splits.firstIndex(where: { $0.contains(id) }), splits[at].count == 2 else {
            return self
        }
        let tabs = splits[at].tabs
        var next = self
        next.splits[at] = TabSplit(tabs[0], tabs[1], axis: axis)
        return next
    }

    func swappingRow(containing id: UUID) -> TabSplits {
        guard let sibling = split(containing: id)?.sibling(of: id) else { return self }
        return exchanging(id, sibling)
    }

    func setting(
        seam index: Int,
        inGroupAt path: [Int],
        containing id: UUID,
        leading: CGFloat,
        minimum: CGFloat
    ) -> TabSplits {
        guard let at = splits.firstIndex(where: { $0.contains(id) }) else { return self }
        var root = splits[at].root
        guard var group = root[path], group.children.indices.contains(index),
              group.children.indices.contains(index + 1)
        else { return self }

        let pair = group.children[index].share + group.children[index + 1].share
        let floor = max(TabSplit.shareRange.lowerBound, min(minimum, 0.5))
        let ceiling = min(TabSplit.shareRange.upperBound, max(1 - minimum, 0.5))
        let share = min(max(leading, floor), max(floor, ceiling))
        group.children[index].share = pair * share
        group.children[index + 1].share = pair * (1 - share)
        root[path] = group

        guard let rebuilt = TabSplit(root: root) else { return self }
        var next = self
        next.splits[at] = rebuilt
        return next
    }

    // MARK: - Reconciliation

    func reconciled(against live: Set<UUID>) -> TabSplits {
        var seen: Set<UUID> = []
        let kept = splits.compactMap { split -> TabSplit? in
            guard let pruned = split.root.pruned(to: live, seen: &seen) else { return nil }
            return TabSplit(root: pruned)
        }
        return TabSplits(kept)
    }
}
