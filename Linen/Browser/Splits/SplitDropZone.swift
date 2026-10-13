// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import Foundation

nonisolated enum SplitDropZone: Hashable, Sendable {
    case none
    case left
    case right
    case top
    case bottom
    case centre

    static let edges: [SplitDropZone] = [.left, .right, .top, .bottom]

    var axis: SplitAxis? {
        switch self {
        case .none, .centre:
            nil
        case .left, .right:
            .sideBySide
        case .top, .bottom:
            .stacked
        }
    }

    var placesDroppedTabFirst: Bool {
        self == .left || self == .top
    }
}
