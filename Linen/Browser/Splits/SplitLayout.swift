// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import Foundation

nonisolated struct SplitSeam: Equatable, Sendable, Identifiable {
    let groupPath: [Int]
    let index: Int
    let axis: SplitAxis
    let rect: CGRect
    let pairRect: CGRect

    var id: String {
        groupPath.map(String.init).joined(separator: ".") + ":\(index)"
    }

    var divisibleLength: CGFloat {
        let span = axis == .sideBySide ? pairRect.width : pairRect.height
        let gutter = axis == .sideBySide ? rect.width : rect.height
        return max(0, span - gutter)
    }

    func leadingShare(at point: CGPoint) -> CGFloat {
        guard divisibleLength > 0 else { return 0.5 }
        let sideways = axis == .sideBySide
        let along = (sideways ? point.x : point.y) - (sideways ? pairRect.minX : pairRect.minY)
        let gutter = sideways ? rect.width : rect.height
        return (along - gutter / 2) / divisibleLength
    }

    func minimumShare(_ length: CGFloat) -> CGFloat {
        guard divisibleLength > 0 else { return 0.5 }
        return min(length / divisibleLength, 0.5)
    }
}

nonisolated struct SplitLayout: Equatable, Sendable {
    let grid: TabSplit
    let size: CGSize
    let gutter: CGFloat

    private(set) var slots: [UUID: CGRect] = [:]
    private(set) var seams: [SplitSeam] = []
    private(set) var groups: [[Int]: CGRect] = [:]

    init(grid: TabSplit, size: CGSize, gutter: CGFloat) {
        self.grid = grid
        self.size = size
        self.gutter = gutter
        place(grid.root, in: CGRect(origin: .zero, size: size), at: [])
    }

    func slot(of id: UUID) -> CGRect? {
        slots[id]
    }

    func isUnderTopBar(_ id: UUID) -> Bool {
        grid.isUnderTopBar(id)
    }

    private mutating func place(_ node: SplitNode, in rect: CGRect, at path: [Int]) {
        switch node.content {
        case .page(let id):
            slots[id] = rect
        case .group(let axis, let children):
            groups[path] = rect
            let sideways = axis == .sideBySide
            let length = sideways ? rect.width : rect.height
            let usable = max(0, length - gutter * CGFloat(children.count - 1))
            var offset: CGFloat = sideways ? rect.minX : rect.minY
            var placed: [CGRect] = []

            for child in children {
                let span = usable * child.share
                let box = sideways
                    ? CGRect(x: offset, y: rect.minY, width: span, height: rect.height)
                    : CGRect(x: rect.minX, y: offset, width: rect.width, height: span)
                placed.append(box)
                place(child, in: box, at: path + [placed.count - 1])
                offset += span + gutter
            }

            for index in placed.indices.dropLast() {
                let before = placed[index]
                let after = placed[index + 1]
                let strip = sideways
                    ? CGRect(x: before.maxX, y: rect.minY, width: gutter, height: rect.height)
                    : CGRect(x: rect.minX, y: before.maxY, width: rect.width, height: gutter)
                seams.append(SplitSeam(
                    groupPath: path,
                    index: index,
                    axis: axis,
                    rect: strip,
                    pairRect: before.union(after)
                ))
            }
        }
    }
}
