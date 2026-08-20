// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics

enum SidebarDropBand: Equatable {
    case before
    case after
    case fold
    case split(leading: Bool)
}

enum SidebarDropGeometry {
    static let singleRowHeight: CGFloat = 32

    static func reorderEdgeHeight(rowHeight: CGFloat) -> CGFloat {
        0.32 * min(rowHeight, singleRowHeight)
    }

    static func probeY(cursorY: CGFloat, carriedMidY: CGFloat, carriedHeight: CGFloat) -> CGFloat {
        carriedHeight > singleRowHeight + 1 ? cursorY : carriedMidY
    }

    static func folderBand(y: CGFloat, in frame: CGRect) -> SidebarDropBand {
        let relative = (y - frame.minY) / max(frame.height, 1)
        if relative < 0.3 {
            return .before
        }
        if relative > 0.7 {
            return .after
        }
        return .fold
    }

    static func folderedTabBand(y: CGFloat, in frame: CGRect) -> SidebarDropBand {
        y < frame.midY ? .before : .after
    }

    static func looseTabBand(
        at point: CGPoint,
        in frame: CGRect,
        canFold: Bool,
        canSplit: Bool,
        splitEndWidth: CGFloat
    ) -> SidebarDropBand {
        let edge = reorderEdgeHeight(rowHeight: frame.height)
        if point.y < frame.minY + edge {
            return .before
        }
        if point.y >= frame.maxY - edge {
            return .after
        }
        if canSplit {
            if point.x < frame.minX + splitEndWidth {
                return .split(leading: true)
            }
            if point.x > frame.maxX - splitEndWidth {
                return .split(leading: false)
            }
        }
        if canFold {
            return .fold
        }
        return point.y < frame.midY ? .before : .after
    }
}
