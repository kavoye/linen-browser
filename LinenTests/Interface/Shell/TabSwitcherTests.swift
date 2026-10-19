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
        _ = model.newTab()

        model.switchTab(forward: true)
        model.switchTab(forward: true)
        model.endTabSwitching()

        #expect(model.activeTab === third)
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

    @Test func aShortRowIsOnlyAsWideAsItsCards() {
        let three = TabSwitcherOverlay.rowWidth(count: 3, available: 5000)
        let four = TabSwitcherOverlay.rowWidth(count: 4, available: 5000)
        #expect(four > three)
    }

    @Test func aLongRowStopsAtSevenCards() {
        let seven = TabSwitcherOverlay.rowWidth(count: 7, available: 5000)
        #expect(TabSwitcherOverlay.rowWidth(count: 30, available: 5000) == seven)
    }

    @Test func aRowNeverOverflowsTheWindow() {
        #expect(TabSwitcherOverlay.rowWidth(count: 30, available: 800) == CGFloat(800 - 48))
    }

    @Test func aVisibleCardDoesNotMoveTheRow() {
        #expect(TabSwitcherOverlay.offset(revealing: 1, from: 0, viewport: 1000) == nil)
    }

    @Test func aCardPastTheTrailingEdgeKeepsTheRowMargin() {
        let viewport = TabSwitcherOverlay.rowWidth(count: 3, available: 5000)
        let target = TabSwitcherOverlay.offset(revealing: 3, from: 0, viewport: viewport)
        let fourth = TabSwitcherOverlay.rowWidth(count: 4, available: 5000)
        #expect(target == fourth - viewport)
    }

    @Test func aCardPastTheLeadingEdgeKeepsTheRowMargin() {
        let step = TabSwitcherOverlay.rowWidth(count: 2, available: 5000)
            - TabSwitcherOverlay.rowWidth(count: 1, available: 5000)
        #expect(TabSwitcherOverlay.offset(revealing: 2, from: 3 * step, viewport: 1000) == 2 * step)
    }

    // MARK: - Closing from the switcher

    @Test func closingTheSelectedCardSelectsTheOneThatTakesItsPlace() {
        let model = makeModel()
        _ = model.newTab()
        _ = model.newTab()
        _ = model.newTab()

        model.switchTab(forward: true)
        let order = model.switcherTabs
        let closed = order[1]
        model.close(closed)

        #expect(model.isSwitchingTabs)
        #expect(model.switcherSelection == order[2].id)
    }

    @Test func closingAnotherCardKeepsTheSelection() {
        let model = makeModel()
        _ = model.newTab()
        _ = model.newTab()
        _ = model.newTab()

        model.switchTab(forward: true)
        let selected = model.switcherSelection
        model.close(model.switcherTabs[2])

        #expect(model.switcherSelection == selected)
    }

    @Test func closingEveryTabClosesTheSwitcher() {
        let model = makeModel()
        let first = model.newTab()
        let second = model.newTab()

        model.switchTab(forward: true)
        model.close(first)
        model.close(second)

        #expect(!model.isSwitchingTabs)
    }

    @Test func aClickOnACardGoesToThatTab() {
        let model = makeModel()
        let chosen = model.newTab()
        _ = model.newTab()
        _ = model.newTab()

        model.switchTab(forward: true)
        model.endTabSwitching(choosing: chosen.id)

        #expect(model.activeTab === chosen)
        #expect(!model.isSwitchingTabs)
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
