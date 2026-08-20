// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct TabSwitcherTests {
    private func makeModel() -> BrowserModel {
        BrowserModel(database: .temporary())
    }

    // MARK: - Holding the modifier

    @Test func holdingAndSteppingGoesToTheTabBelow() {
        let model = makeModel()
        _ = model.newTab()
        let below = model.newTab()
        let start = model.newTab()
        let elsewhere = model.newTab()
        model.activate(elsewhere)
        model.activate(start)

        model.switchTab(forward: true)
        model.endTabSwitching()

        #expect(model.activeTab === below)
    }

    @Test func holdingAndSteppingBackGoesToTheTabAbove() {
        let model = makeModel()
        _ = model.newTab()
        let start = model.newTab()
        let above = model.newTab()
        let elsewhere = model.newTab()
        model.activate(elsewhere)
        model.activate(start)

        model.switchTab(forward: false)
        model.endTabSwitching()

        #expect(model.activeTab === above)
    }

    @Test func everyStepOfAHoldMovesOneRowFurther() {
        let model = makeModel()
        _ = model.newTab()
        let third = model.newTab()
        let second = model.newTab()
        let start = model.newTab()

        model.switchTab(forward: true)
        #expect(model.activeTab === second)

        model.switchTab(forward: true)
        #expect(model.activeTab === third)

        model.endTabSwitching()
        _ = start
    }

    @Test func aHoldNeverDetoursThroughTheTabYouCameFrom() {
        let model = makeModel()
        _ = model.newTab()
        let below = model.newTab()
        let start = model.newTab()
        let elsewhere = model.newTab()
        model.activate(elsewhere)
        model.activate(start)

        model.switchTab(forward: true, asTap: false)

        #expect(model.activeTab === below)
        #expect(model.activeTab !== elsewhere)
        model.endTabSwitching()
    }

    @Test func theWalkWrapsPastTheEndOfTheList() {
        let model = makeModel()
        let bottom = model.newTab()
        _ = model.newTab()
        let top = model.newTab()
        model.activate(bottom)

        model.switchTab(forward: true)
        model.endTabSwitching()

        #expect(model.activeTab === top)
    }

    // MARK: - A quick tap

    @Test func aTapGoesToTheTabYouCameFrom() {
        let model = makeModel()
        _ = model.newTab()
        let previous = model.newTab()
        _ = model.newTab()
        let start = model.newTab()
        model.activate(previous)
        model.activate(start)

        model.switchTab(forward: true, asTap: true)
        model.endTabSwitching()

        #expect(model.activeTab === previous)
    }

    @Test func tappingTwiceReturnsToWhereYouStarted() {
        let model = makeModel()
        _ = model.newTab()
        let previous = model.newTab()
        _ = model.newTab()
        let start = model.newTab()
        model.activate(previous)
        model.activate(start)

        model.switchTab(forward: true, asTap: true)
        model.endTabSwitching()
        model.switchTab(forward: true, asTap: true)
        model.endTabSwitching()

        #expect(model.activeTab === start)
    }

    @Test func aTapWithNoHistoryFallsBackToTheTabBelow() {
        let model = makeModel()
        let below = model.newTab()
        let start = model.newTab()
        model.recentlyActive = [start.id]

        model.switchTab(forward: true, asTap: true)
        model.endTabSwitching()

        #expect(model.activeTab === below)
    }

    @Test func aTapOnALoneTabChangesNothing() {
        let model = makeModel()
        let only = model.newTab()

        model.switchTab(forward: true, asTap: true)
        model.endTabSwitching()

        #expect(model.activeTab === only)
    }

    /// The tap is only the opening move; a hold that carries on steps down from where it landed.
    @Test func steppingOnAfterATapCarriesOnBelowWhereItLanded() {
        let model = makeModel()
        let under = model.newTab()
        let previous = model.newTab()
        _ = model.newTab()
        let start = model.newTab()
        model.activate(previous)
        model.activate(start)

        model.switchTab(forward: true, asTap: true)
        #expect(model.activeTab === previous)

        model.switchTab(forward: true, asTap: true)
        model.endTabSwitching()

        #expect(model.activeTab === under)
    }

    // MARK: - What the walk leaves behind

    @Test func onlyTheTabYouLandOnCountsAsRecent() {
        let model = makeModel()
        _ = model.newTab()
        let third = model.newTab()
        _ = model.newTab()
        let start = model.newTab()

        model.switchTab(forward: true)
        model.switchTab(forward: true)
        model.endTabSwitching()

        #expect(model.activeTab === third)
        #expect(model.previouslyActiveTabID == start.id)
    }

    @Test func aTapAfterAWalkGoesBackToWhereTheWalkBegan() {
        let model = makeModel()
        _ = model.newTab()
        let third = model.newTab()
        _ = model.newTab()
        let start = model.newTab()

        model.switchTab(forward: true)
        model.switchTab(forward: true)
        model.endTabSwitching()
        #expect(model.activeTab === third)

        model.switchTab(forward: true, asTap: true)
        model.endTabSwitching()

        #expect(model.activeTab === start)
    }

    // MARK: - Telling a tap from a hold

    @Test func aChordPressedRightAfterTheModifierIsATap() {
        #expect(ModifierTap.isTap(downAt: 10, now: 10.02))
        #expect(ModifierTap.isTap(downAt: 10, now: 10.11))
    }

    @Test func aPressAfterTheModifierHasSettledIsAHold() {
        #expect(!ModifierTap.isTap(downAt: 10, now: 10.13))
        #expect(!ModifierTap.isTap(downAt: 10, now: 10.3))
        #expect(!ModifierTap.isTap(downAt: 10, now: 12))
    }

    @Test func aPressWithTheModifierUpIsNeverATap() {
        #expect(!ModifierTap.isTap(downAt: nil, now: 10))
    }
}
