// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import Foundation
import Testing

@testable import Linen

struct MediaCropMathTests {
    @Test func fullyVisiblePlayerCropsToItself() {
        let crop = MediaCropMath.visibleCrop(
            viewportRect: CGRect(x: 100, y: 50, width: 640, height: 360),
            viewBounds: CGRect(x: 0, y: 0, width: 1280, height: 800),
            topInset: 0
        )
        #expect(crop == CGRect(x: 100, y: 50, width: 640, height: 360))
    }

    @Test func topInsetShiftsThePlayerDownIntoViewCoordinates() {
        let crop = MediaCropMath.visibleCrop(
            viewportRect: CGRect(x: 100, y: 0, width: 640, height: 360),
            viewBounds: CGRect(x: 0, y: 0, width: 1280, height: 800),
            topInset: 52
        )
        #expect(crop == CGRect(x: 100, y: 52, width: 640, height: 360))
    }

    @Test func playerScrolledPartlyOutClampsToTheViewport() {
        let crop = MediaCropMath.visibleCrop(
            viewportRect: CGRect(x: 0, y: -100, width: 640, height: 360),
            viewBounds: CGRect(x: 0, y: 0, width: 1280, height: 800),
            topInset: 0
        )
        #expect(crop == CGRect(x: 0, y: 0, width: 640, height: 260))
    }

    @Test func playerScrolledAwayHasNoCrop() {
        let crop = MediaCropMath.visibleCrop(
            viewportRect: CGRect(x: 0, y: -340, width: 640, height: 360),
            viewBounds: CGRect(x: 0, y: 0, width: 1280, height: 800),
            topInset: 0
        )
        #expect(crop == nil)
    }

    @Test func cardHeightFollowsTheCropAspect() {
        let height = MediaCropMath.cardHeight(
            width: 320,
            crop: CGRect(x: 0, y: 0, width: 640, height: 360)
        )
        #expect(height == 180)
    }

    @Test func cardHeightIsClampedForVerticalVideo() {
        let height = MediaCropMath.cardHeight(
            width: 320,
            crop: CGRect(x: 0, y: 0, width: 360, height: 640)
        )
        #expect(height == 320)
    }

    @Test func scaledBoundsShowExactlyTheCropAtMatchingAspect() {
        let bounds = MediaCropMath.scaledBounds(
            cardSize: CGSize(width: 320, height: 180),
            crop: CGRect(x: 100, y: 52, width: 640, height: 360)
        )
        #expect(bounds == CGRect(x: 100, y: 52, width: 640, height: 360))
    }

    @Test func scaledBoundsCenterVerticallyWhenTheCardIsShorter() {
        let bounds = MediaCropMath.scaledBounds(
            cardSize: CGSize(width: 320, height: 160),
            crop: CGRect(x: 0, y: 0, width: 640, height: 360)
        )
        #expect(bounds == CGRect(x: 0, y: 20, width: 640, height: 320))
    }
}
