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

    // MARK: - A quick tap

    @Test func aTapGoesToTheTabYouCameFrom() {
        let model = makeModel()
        _ = model.newTab()
        let previous = model.newTab()
        _ = model.newTab()
        let start = model.newTab()
        model.activate(previous)
        model.activate(start)

        model.switchTab(forward: true)
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

        model.switchTab(forward: true)
        model.endTabSwitching()
        model.switchTab(forward: true)
        model.endTabSwitching()

        #expect(model.activeTab === start)
    }

    @Test func aTapOnALoneTabChangesNothing() {
        let model = makeModel()
        let only = model.newTab()

        model.switchTab(forward: true)
        model.endTabSwitching()

        #expect(model.activeTab === only)
        #expect(!model.isSwitchingTabs)
    }

    // MARK: - Holding the modifier

    @Test func everyStepOfAHoldGoesOneTabFurtherBack() {
        let model = makeModel()
        let oldest = model.newTab()
        let older = model.newTab()
        let previous = model.newTab()
        let start = model.newTab()

        model.switchTab(forward: true)
        #expect(model.switcherSelection == previous.id)

        model.switchTab(forward: true)
        #expect(model.switcherSelection == older.id)

        model.switchTab(forward: true)
        #expect(model.switcherSelection == oldest.id)

        model.switchTab(forward: true)
        #expect(model.switcherSelection == start.id)
        model.endTabSwitching()
    }

    @Test func steppingBackFirstReachesTheLeastRecentTab() {
        let model = makeModel()
        let oldest = model.newTab()
        _ = model.newTab()
        _ = model.newTab()

        model.switchTab(forward: false)
        model.endTabSwitching()

        #expect(model.activeTab === oldest)
    }

    @Test func theActiveTabStaysUntilTheModifierIsReleased() {
        let model = makeModel()
        _ = model.newTab()
        _ = model.newTab()
        let start = model.newTab()

        model.switchTab(forward: true)
        model.switchTab(forward: true)

        #expect(model.activeTab === start)
        model.endTabSwitching()
        #expect(model.activeTab !== start)
    }

    @Test func theOrderFollowsRecencyNotTheSidebar() {
        let model = makeModel()
        let first = model.newTab()
        let second = model.newTab()
        let third = model.newTab()
        model.activate(first)
        model.activate(third)

        model.switchTab(forward: true)

        #expect(model.switcherTabs.map(\.id) == [third.id, first.id, second.id])
        model.endTabSwitching()
        #expect(model.activeTab === first)
    }

    @Test func tabsNeverVisitedFollowInSidebarOrder() {
        let model = makeModel()
        let first = model.newTab()
        _ = model.newTab()
        _ = model.newTab()
        model.activate(first)
        model.recentlyActive = [first.id]

        model.switchTab(forward: true)

        #expect(model.switcherTabs.map(\.id) == [first.id] + model.tabs.map(\.id).filter { $0 != first.id })
        #expect(model.switcherSelection == model.tabs.first { $0 !== first }?.id)
        model.cancelTabSwitching()
    }

    // MARK: - Leaving the switcher

    @Test func cancellingKeepsTheTabYouStartedOn() {
        let model = makeModel()
        _ = model.newTab()
        _ = model.newTab()
        let start = model.newTab()

        model.switchTab(forward: true)
        model.cancelTabSwitching()
        model.endTabSwitching()

        #expect(model.activeTab === start)
        #expect(!model.isSwitchingTabs)
    }

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

        model.switchTab(forward: true)
        model.endTabSwitching()

        #expect(model.activeTab === start)
    }

    // MARK: - Which cards fit

    @Test func everyCardShowsWhenThereIsRoom() {
        #expect(TabSwitcherOverlay.window(count: 4, selected: 3, fitting: 7) == 0..<4)
    }

    @Test func theSelectionStaysNearTheMiddleOfALongRow() {
        #expect(TabSwitcherOverlay.window(count: 12, selected: 0, fitting: 5) == 0..<5)
        #expect(TabSwitcherOverlay.window(count: 12, selected: 6, fitting: 5) == 4..<9)
        #expect(TabSwitcherOverlay.window(count: 12, selected: 11, fitting: 5) == 7..<12)
    }

    // MARK: - Shift steps back

    @Test func aShiftTapDuringAHoldStepsBack() {
        var step = ShiftStep()
        step.shiftDown(whileSwitching: true)
        let stepped = step.shiftUp()
        #expect(stepped)
    }

    @Test func shiftAloneDoesNotOpenTheSwitcher() {
        var step = ShiftStep()
        step.shiftDown(whileSwitching: false)
        let stepped = step.shiftUp()
        #expect(!stepped)
    }

    @Test func shiftWithTabStepsOnlyOnce() {
        var step = ShiftStep()
        step.shiftDown(whileSwitching: true)
        step.cancel()
        let stepped = step.shiftUp()
        #expect(!stepped)
    }

    @Test func aShiftTapCountsOnlyOnce() {
        var step = ShiftStep()
        step.shiftDown(whileSwitching: true)
        _ = step.shiftUp()
        let stepped = step.shiftUp()
        #expect(!stepped)
    }
}
