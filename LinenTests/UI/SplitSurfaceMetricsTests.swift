// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import Foundation
import Testing

@testable import Linen

/// The middle magnet's click: once per crossing, quiet while the hand rests
/// inside the zone, and again on the way back in.
struct SplitSeamSnapTests {
    @Test func theMagnetClicksOncePerCrossing() {
        var tracker = SeamSnapTracker()

        let entering = tracker.resolve(0.51, over: 1000)
        #expect(entering.share == 0.5)
        #expect(entering.snapped)

        let resting = tracker.resolve(0.505, over: 1000)
        #expect(resting.share == 0.5)
        #expect(!resting.snapped)

        let leaving = tracker.resolve(0.6, over: 1000)
        #expect(leaving.share == 0.6)
        #expect(!leaving.snapped)

        let returning = tracker.resolve(0.499, over: 1000)
        #expect(returning.share == 0.5)
        #expect(returning.snapped)
    }

    @Test func aNewDragStartsWithTheMagnetQuiet() {
        var tracker = SeamSnapTracker()
        _ = tracker.resolve(0.5, over: 1000)
        tracker.reset()
        #expect(tracker.resolve(0.5, over: 1000).snapped)
    }

    @Test func farFromTheMiddleNothingSnaps() {
        var tracker = SeamSnapTracker()
        let result = tracker.resolve(0.3, over: 1000)
        #expect(result.share == 0.3)
        #expect(!result.snapped)
    }

    @Test func theZoneScalesWithTheLine() {
        #expect(SplitMetrics.isCentred(0.45, over: 100))
        #expect(!SplitMetrics.isCentred(0.45, over: 1000))
    }
}

/// The seam's grab band: narrower than the gutter it sits in, centred on the
/// line, full length along it.
struct SplitSeamHitTests {
    @Test func theGrabBandIsNarrowerThanTheGutter() {
        #expect(SplitMetrics.seamHitWidth < SplitMetrics.gutter)
    }

    @Test func anUprightSeamTakesACentredBand() {
        let rect = CGRect(x: 100, y: 0, width: SplitMetrics.gutter, height: 400)
        let hit = SplitMetrics.seamHitRect(in: rect, axis: .sideBySide)
        #expect(hit.width == SplitMetrics.seamHitWidth)
        #expect(hit.height == 400)
        #expect(abs(hit.midX - rect.midX) < 0.001)
    }

    @Test func aFlatSeamTakesACentredBand() {
        let rect = CGRect(x: 0, y: 50, width: 400, height: SplitMetrics.gutter)
        let hit = SplitMetrics.seamHitRect(in: rect, axis: .stacked)
        #expect(hit.height == SplitMetrics.seamHitWidth)
        #expect(hit.width == 400)
        #expect(abs(hit.midY - rect.midY) < 0.001)
    }
}

/// The grip's presence: dim over the page, full under the pointer, gone while
/// a page is in the air.
struct SplitPillVisibilityTests {
    @Test func thePillRestsDimOverThePage() {
        let resting = SplitPillVisibility.opacity(isHidden: false, isHovered: false, isDragging: false, isSettled: true)
        #expect(resting == SplitPillVisibility.resting)
        #expect(resting > 0)
        #expect(resting < 1)
    }

    @Test func thePillArrivesAtFullAndOnlyThenSettles() {
        #expect(SplitPillVisibility.opacity(isHidden: false, isHovered: false, isDragging: false, isSettled: false) == 1)
        #expect(SplitPillVisibility.settleDelay > .zero)
    }

    @Test func thePointerBringsThePillUpToFull() {
        #expect(SplitPillVisibility.opacity(isHidden: false, isHovered: true, isDragging: false, isSettled: true) == 1)
        #expect(SplitPillVisibility.opacity(isHidden: false, isHovered: false, isDragging: true, isSettled: true) == 1)
    }

    @Test func aCarriedPageHidesEveryPill() {
        #expect(SplitPillVisibility.opacity(isHidden: true, isHovered: false, isDragging: false, isSettled: true) == 0)
        #expect(SplitPillVisibility.opacity(isHidden: true, isHovered: true, isDragging: false, isSettled: false) == 0)
    }

    /// The glass may only stand where the pill is already at full: a material
    /// carried at a part opacity ghosts grey instead of fading.
    @Test func onlyAFullyPresentPillMayWearGlass() {
        for hidden in [true, false] {
            for hovered in [true, false] {
                for dragging in [true, false] {
                    for settled in [true, false] {
                        let engaged = SplitPillVisibility.isEngaged(
                            isHidden: hidden, isHovered: hovered,
                            isDragging: dragging, isSettled: settled
                        )
                        let opacity = SplitPillVisibility.opacity(
                            isHidden: hidden, isHovered: hovered,
                            isDragging: dragging, isSettled: settled
                        )
                        #expect(engaged == (opacity == 1))
                    }
                }
            }
        }
    }
}
