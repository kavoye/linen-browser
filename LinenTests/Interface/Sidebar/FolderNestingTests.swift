// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import Testing

@testable import Linen

@MainActor
struct FolderNestingTests {
    @Test func theTopLevelOutlineIsAPlainControlCorner() {
        #expect(FolderSection.outlineRadius(depth: 0) == Theme.Radius.control)
    }

    @Test func eachLevelDrawsInsideTheOneAboveIt() {
        for depth in 0..<6 {
            #expect(
                FolderSection.outlineRadius(depth: depth + 1) <= FolderSection.outlineRadius(depth: depth),
                "\(depth)"
            )
        }
    }

    @Test func aLevelShrinksByTheInsetItIsDrawnWith() {
        #expect(
            FolderSection.outlineRadius(depth: 1)
                == Theme.Radius.control - FolderSection.outlineInset
        )
    }

    @Test func aRowIsNeverRounderThanTheOutlineAroundIt() {
        for depth in 0..<40 {
            #expect(FolderSection.rowRadius(depth: depth) <= FolderSection.outlineRadius(depth: depth), "\(depth)")
        }
    }

    @Test func aRowIsStrictlyTighterWhileThereIsRoomToShrink() {
        for depth in 0..<6 where FolderSection.outlineRadius(depth: depth) > Theme.Radius.tight {
            #expect(FolderSection.rowRadius(depth: depth) < FolderSection.outlineRadius(depth: depth), "\(depth)")
        }
    }

    @Test func deepNestingStopsAtTheTightestCornerInsteadOfInverting() {
        for depth in 0..<40 {
            #expect(FolderSection.outlineRadius(depth: depth) >= Theme.Radius.tight, "\(depth)")
            #expect(FolderSection.rowRadius(depth: depth) >= Theme.Radius.tight, "\(depth)")
        }
        #expect(FolderSection.outlineRadius(depth: 30) == Theme.Radius.tight)
    }

    @Test func aNegativeDepthIsReadAsTheTopLevel() {
        #expect(FolderSection.outlineRadius(depth: -3) == FolderSection.outlineRadius(depth: 0))
    }

    @Test func theInsetIsAVisibleAmount() {
        #expect(FolderSection.outlineInset > 0)
    }
}
