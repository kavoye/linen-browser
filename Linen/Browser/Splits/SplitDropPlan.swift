// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import Foundation

nonisolated struct SplitDropPlan: Equatable, Sendable {
    nonisolated struct Target: Equatable, Sendable {
        let anchor: UUID
        let edge: SplitDropZone
        let slot: CGRect
        let displaces: Bool
    }

    private(set) var targets: [Target] = []
    private(set) var panes: [UUID: CGRect] = [:]
    private var windowSize: CGSize = .zero

    init() {}

    init(singlePage id: UUID, size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let half = CGSize(width: size.width / 2, height: size.height / 2)
        panes = [id: CGRect(origin: .zero, size: size)]
        windowSize = size
        targets = [
            Target(anchor: id, edge: .left,
                   slot: CGRect(origin: .zero, size: CGSize(width: half.width, height: size.height)),
                   displaces: false),
            Target(anchor: id, edge: .right,
                   slot: CGRect(x: half.width, y: 0, width: half.width, height: size.height),
                   displaces: false),
            Target(anchor: id, edge: .top,
                   slot: CGRect(origin: .zero, size: CGSize(width: size.width, height: half.height)),
                   displaces: false),
            Target(anchor: id, edge: .bottom,
                   slot: CGRect(x: 0, y: half.height, width: size.width, height: half.height),
                   displaces: false),
        ]
    }

    init(grid: TabSplit, size: CGSize, gutter: CGFloat, carrying carried: UUID? = nil) {
        guard size.width > 0, size.height > 0 else {
            self.init()
            return
        }
        guard let carried, grid.contains(carried) else {
            self.init(base: grid, size: size, gutter: gutter)
            return
        }
        if let rest = TabSplits([grid]).removing(carried).splits.first {
            self.init(base: rest, size: size, gutter: gutter)
        } else if let survivor = grid.tabs.first(where: { $0 != carried }) {
            self.init(singlePage: survivor, size: size)
        } else {
            self.init()
        }
    }

    private init(base: TabSplit, size: CGSize, gutter: CGFloat) {
        let arriving = UUID()
        let resting = SplitLayout(grid: base, size: size, gutter: gutter)
        var found: [Target] = []

        for anchor in base.tabs {
            guard let home = resting.slot(of: anchor) else { continue }
            panes[anchor] = home
            append(Target(anchor: anchor, edge: .centre, slot: home, displaces: true),
                   to: &found, ownSlot: home)

            for edge in SplitDropZone.edges {
                guard let result = TabSplits([base])
                    .inserting(arriving, beside: anchor, edge: edge)
                    .split(containing: arriving),
                    let slot = SplitLayout(grid: result, size: size, gutter: gutter).slot(of: arriving)
                else { continue }
                append(
                    Target(anchor: anchor, edge: edge, slot: slot, displaces: result.count == base.count),
                    to: &found,
                    ownSlot: home
                )
            }
        }
        targets = found
        windowSize = size
    }

    private func append(_ target: Target, to found: inout [Target], ownSlot: CGRect) {
        guard let same = found.firstIndex(where: {
            $0.slot == target.slot && $0.displaces == target.displaces
        }) else {
            found.append(target)
            return
        }
        if target.slot == ownSlot {
            found[same] = target
        }
    }

    static let stackedBand: CGFloat = 0.25

    func target(at point: CGPoint) -> Target? {
        guard let (anchor, home) = panes.first(where: { $0.value.contains(point) }) else {
            return nearest(to: point, among: targets)
        }
        let asked = targets.filter { $0.anchor == anchor }
        guard asked.count > 1 else { return asked.first ?? nearest(to: point, among: targets) }

        let fullWidth = home.width >= windowSize.width - 1
        let fullHeight = home.height >= windowSize.height - 1
        let edge: SplitDropZone
        if fullWidth, fullHeight {
            let dx = (point.x - home.midX) / max(home.width, 1)
            let dy = (point.y - home.midY) / max(home.height, 1)
            edge = abs(dy) > Self.stackedBand && abs(dy) > abs(dx)
                ? (dy < 0 ? .top : .bottom)
                : (dx < 0 ? .left : .right)
        } else if fullWidth {
            edge = point.x < home.midX ? .left : .right
        } else if fullHeight {
            edge = point.y < home.midY ? .top : .bottom
        } else {
            edge = .centre
        }
        return asked.first { $0.edge == edge } ?? nearest(to: point, among: asked)
    }

    private func nearest(to point: CGPoint, among candidates: [Target]) -> Target? {
        candidates.min { one, other in
            distance(from: point, to: one.slot) < distance(from: point, to: other.slot)
        }
    }

    private func distance(from point: CGPoint, to slot: CGRect) -> CGFloat {
        let dx = point.x - slot.midX
        let dy = point.y - slot.midY
        return dx * dx + dy * dy
    }
}
