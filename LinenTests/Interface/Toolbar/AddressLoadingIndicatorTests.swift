// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Testing

@testable import Linen

struct AddressLoadingIndicatorTests {
    @Test func idleTabsNeverShowACompletedBar() {
        var animation = AddressLoadingAnimation()
        animation.update(AddressLoadingInput(progress: 1, isLoading: false), at: 0)
        #expect(animation.frame(at: 1).opacity == 0)
        #expect(!animation.hasProgress)
    }

    @Test func startsSmallAndAdvancesSmoothlyWithoutOrdinaryRegressions() {
        var animation = AddressLoadingAnimation()
        animation.update(AddressLoadingInput(progress: 0, isLoading: true), at: 0)
        #expect(animation.frame(at: 0.2).progress > 0)
        animation.update(AddressLoadingInput(progress: 0.7, isLoading: true), at: 1)
        let midway = animation.frame(at: 1.09).progress
        #expect(midway > 0 && midway < 0.7)
        animation.update(AddressLoadingInput(progress: 0.6, isLoading: true), at: 1.1)
        #expect(animation.frame(at: 1.6).progress > midway)
    }

    @Test func keepsMovingWhenNoNewCheckpointArrives() {
        var animation = AddressLoadingAnimation()
        animation.update(AddressLoadingInput(progress: 0.2, isLoading: true), at: 0)
        let afterCheckpoint = animation.frame(at: 0.8).progress
        #expect(afterCheckpoint > 0.2)
        #expect(animation.frame(at: 1.2).progress > afterCheckpoint)
        #expect(animation.frame(at: 3).progress < 1)
        let firstStep = animation.frame(at: 1.1).progress - animation.frame(at: 1).progress
        let secondStep = animation.frame(at: 1.2).progress - animation.frame(at: 1.1).progress
        #expect(abs(firstStep - secondStep) < 0.001)
    }

    @Test func newCheckpointRetargetsWithoutStoppingAtTheOldOne() {
        var animation = AddressLoadingAnimation()
        animation.update(AddressLoadingInput(progress: 0.2, isLoading: true), at: 0)
        animation.update(AddressLoadingInput(progress: 0.5, isLoading: true), at: 0.1)
        let beforeRetarget = animation.frame(at: 0.2).progress
        animation.update(AddressLoadingInput(progress: 0.9, isLoading: true), at: 0.2)
        #expect(abs(animation.frame(at: 0.2).progress - beforeRetarget) < 0.000001)
        #expect(animation.frame(at: 0.3).progress > beforeRetarget)
        #expect(animation.frame(at: 0.8).progress > 0.5)
    }

    @Test func finishingFillsThenSweepsAway() {
        var animation = AddressLoadingAnimation()
        animation.update(AddressLoadingInput(progress: 0.4, isLoading: true), at: 0)
        animation.update(AddressLoadingInput(progress: 0.4, isLoading: false), at: 1)
        #expect(animation.frame(at: 1.1).progress > 0.4)
        #expect(animation.frame(at: 1.1).exit == 0)
        let fading = animation.frame(at: 1 + animation.completionDuration(at: 1) - AddressLoadingAnimation.fadeDuration / 2)
        #expect(fading.progress == 1)
        #expect(fading.exit > 0 && fading.exit < 1)
        #expect(fading.opacity > 0 && fading.opacity < 1)
        #expect(animation.frame(at: 1 + animation.completionDuration(at: 1)).opacity == 0)
    }

    @Test func completionRetargetsFromTheCurrentPosition() {
        var animation = AddressLoadingAnimation()
        animation.update(AddressLoadingInput(progress: 0.7, isLoading: true), at: 0)
        let beforeCompletion = animation.frame(at: 0.2).progress
        animation.update(AddressLoadingInput(progress: 0.7, isLoading: false), at: 0.2)
        #expect(animation.frame(at: 0.2).progress == beforeCompletion)
        #expect(animation.frame(at: 0.3).progress > beforeCompletion)
        #expect(animation.frame(at: 0.3).exit == 0)
        let finish = 0.2 + animation.completionDuration(at: 0.2) - AddressLoadingAnimation.fadeDuration
        #expect(abs(animation.frame(at: finish).progress - 1) < 0.000001)
        #expect(animation.frame(at: finish).exit == 0)
        #expect(animation.frame(at: finish + AddressLoadingAnimation.fadeDuration).opacity == 0)
    }

    @Test func aNewLoadInterruptsTheCompletionFade() {
        var animation = AddressLoadingAnimation()
        animation.update(AddressLoadingInput(progress: 0.8, isLoading: true), at: 0)
        animation.update(AddressLoadingInput(progress: 1, isLoading: false), at: 1)
        animation.update(AddressLoadingInput(progress: 0.1, isLoading: true), at: 1.3)
        let next = animation.frame(at: 1.6)
        #expect(next.progress > 0 && next.progress < 0.1)
        #expect(next.opacity == 1)
        #expect(next.exit == 0)
    }

    @Test func replacingAnInFlightNavigationRestartsProgress() {
        var animation = AddressLoadingAnimation()
        animation.update(AddressLoadingInput(progress: 0.8, isLoading: true), at: 0)
        animation.update(AddressLoadingInput(progress: 0.1, isLoading: true), at: 1)
        #expect(animation.frame(at: 1).progress == 0)
        #expect(animation.frame(at: 1.2).progress > 0)
    }

    @Test func reduceMotionHasNoPulseOrCompletionAnimation() {
        var animation = AddressLoadingAnimation()
        animation.update(AddressLoadingInput(progress: 0.5, isLoading: true), at: 0)
        #expect(animation.frame(at: 0, reduceMotion: true).progress == 0.5)
        #expect(animation.frame(at: 0, reduceMotion: true).glow == animation.frame(at: 0.7, reduceMotion: true).glow)
        animation.update(AddressLoadingInput(progress: 1, isLoading: false), at: 1)
        #expect(animation.frame(at: 1, reduceMotion: true).opacity == 0)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -1, 2])
    func invalidProgressStaysWithinTheField(value: Double) {
        var animation = AddressLoadingAnimation()
        animation.update(AddressLoadingInput(progress: value, isLoading: true), at: 0)
        let frame = animation.frame(at: 1)
        #expect(frame.progress.isFinite)
        #expect((0...1).contains(frame.progress))
    }
}
