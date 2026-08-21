// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import Foundation
import Testing

@testable import Linen

/// The right side is one place that holds tabs. These pin the rules that make
/// it feel like a place: what opening twice does, what closing leaves behind,
/// and what comes back after a relaunch.
@MainActor
struct SidePanelTests {
    private func panel(_ defaults: UserDefaults? = nil) -> SidePanelModel {
        SidePanelModel(defaults: defaults ?? scratch())
    }

    private func scratch() -> UserDefaults {
        UserDefaults(suiteName: "SidePanelTests-\(UUID().uuidString)")!
    }

    @Test func itStartsClosedWithATabForEveryKind() {
        let panel = panel()

        #expect(!panel.isVisible)
        #expect(panel.tabs.map(\.kind) == SidePanelKind.allCases)
        #expect(panel.selectedKind == nil, "nothing is chosen until it is opened once")
    }

    @Test func openingAKindShowsThePanelOnThatTab() {
        let panel = panel()

        panel.show(.lyrics)

        #expect(panel.isVisible)
        #expect(panel.isShowing(.lyrics))
        #expect(!panel.isShowing(.activity))
    }

    @Test func openingAKindTwiceNeverAddsASecondTab() {
        let panel = panel()
        let count = panel.tabs.count
        panel.show(.lyrics)
        panel.show(.activity)

        panel.show(.lyrics)

        #expect(panel.tabs.count == count)
        #expect(panel.isShowing(.lyrics))
    }

    @Test func togglingTheTabYouAreLookingAtHidesThePanel() {
        let panel = panel()
        panel.show(.activity)

        panel.toggle(.activity)

        #expect(!panel.isVisible)
        #expect(panel.isShowing(.activity) == false)
        #expect(panel.selectedKind == .activity, "hiding keeps the choice for next time")
    }

    @Test func togglingAnotherKindSwitchesRatherThanHiding() {
        let panel = panel()
        panel.show(.activity)

        panel.toggle(.lyrics)

        #expect(panel.isVisible)
        #expect(panel.isShowing(.lyrics))
    }

    @Test func hidingThenOpeningComesBackToTheSameTab() {
        let panel = panel()
        panel.show(.lyrics)
        panel.hide()

        panel.show(.lyrics)

        #expect(panel.isShowing(.lyrics))
    }

    @Test func thePanelsOwnButtonReopensWhatWasLastInIt() {
        let panel = panel()
        panel.show(.lyrics)
        panel.hide()

        panel.show(seeding: .activity)

        #expect(panel.isShowing(.lyrics), "the seed only applies to a panel never opened")
    }

    @Test func aFirstOpenTakesTheSeed() {
        let panel = panel()

        panel.show(seeding: .lyrics)

        #expect(panel.isShowing(.lyrics))
    }

    @Test func escapeClosesThePanelOnceAndThenLetsTheKeyThrough() {
        let panel = panel()
        panel.show(.activity)

        #expect(panel.close())
        #expect(!panel.close())
    }

    // MARK: - A kind turned off in Settings

    @Test func aKindTurnedOffHasNoTabAtAll() {
        let panel = panel()

        panel.setAvailable(false, for: .lyrics)

        #expect(panel.tabs.map(\.kind) == [.activity])
    }

    @Test func turningOffTheTabYouAreLookingAtStepsToTheNextOne() {
        let panel = panel()
        panel.show(.lyrics)

        panel.setAvailable(false, for: .lyrics)

        #expect(panel.isShowing(.activity))
    }

    @Test func aKindTurnedOffCannotBeOpened() {
        let panel = panel()
        panel.setAvailable(false, for: .lyrics)

        panel.show(.lyrics)
        panel.toggle(.lyrics)

        #expect(!panel.isVisible)
        #expect(panel.selectedKind == nil)
    }

    @Test func aFirstOpenSeededWithAKindTurnedOffLandsOnWhatIsLeft() {
        let panel = panel()
        panel.setAvailable(false, for: .lyrics)

        panel.show(seeding: .lyrics)

        #expect(panel.isShowing(.activity))
    }

    @Test func turningAKindBackOnBringsItsTabBack() {
        let panel = panel()
        panel.setAvailable(false, for: .lyrics)

        panel.setAvailable(true, for: .lyrics)
        panel.show(.lyrics)

        #expect(panel.isShowing(.lyrics))
    }

    // MARK: - Across a relaunch

    @Test func theTabYouWereOnComesBack() {
        let defaults = scratch()
        let first = panel(defaults)
        first.show(.activity)
        first.show(.lyrics)

        let reopened = panel(defaults)

        #expect(reopened.isShowing(.lyrics))
    }

    @Test func aHiddenPanelStaysHiddenButKeepsItsChoice() {
        let defaults = scratch()
        let first = panel(defaults)
        first.show(.lyrics)
        first.hide()

        let reopened = panel(defaults)

        #expect(!reopened.isVisible)
        #expect(reopened.selectedKind == .lyrics)
    }

    @Test func aPanelNeverOpenedComesBackWithNothingChosen() {
        #expect(panel(scratch()).selectedKind == nil)
    }

    @Test func theWidthAndTheExpandedShapeComeBack() {
        let defaults = scratch()
        let first = panel(defaults)
        first.show(.activity)
        first.dragChanged(translation: -60, container: 1400)
        first.dragEnded(translation: -60, container: 1400)
        first.isExpanded = true
        let width = first.width

        let reopened = panel(defaults)

        #expect(reopened.width == width)
        #expect(reopened.isExpanded)
    }

    // MARK: - Width

    @Test func theWidthStaysWithinItsRange() {
        #expect(SidePanelMetrics.clampWidth(10, container: 1400) == SidePanelMetrics.minWidth)
        #expect(SidePanelMetrics.clampWidth(9000, container: 4000) == SidePanelMetrics.maxWidth)
    }

    @Test func aNarrowWindowCapsThePanelBeforeItsOwnMaximum() {
        let capped = SidePanelMetrics.clampWidth(600, container: 900)

        #expect(capped == 900 * SidePanelMetrics.maxWindowFraction)
        #expect(capped < SidePanelMetrics.maxWidth)
    }

    @Test func aWindowTooSmallForTheMinimumStillGetsTheMinimum() {
        #expect(SidePanelMetrics.clampWidth(400, container: 200) == SidePanelMetrics.minWidth)
    }

    @Test func draggingWiderShowsTheNewWidthBeforeItIsReleased() {
        let panel = panel()
        let start = panel.openWidth(in: 1400)

        panel.dragChanged(translation: -50, container: 1400)

        #expect(panel.isDragging)
        #expect(panel.openWidth(in: 1400) == start + 50)
    }

    @Test func itOpensAsNarrowAsItGoes() {
        #expect(SidePanelMetrics.defaultWidth == SidePanelMetrics.minWidth)
        #expect(panel().openWidth(in: 1400) == SidePanelMetrics.minWidth)
    }

    @Test func theWidthGoesBackToTheDefault() {
        let panel = panel()
        panel.dragChanged(translation: -80, container: 1400)
        panel.dragEnded(translation: -80, container: 1400)
        #expect(panel.width > SidePanelMetrics.defaultWidth)

        panel.resetWidth()

        #expect(panel.width == SidePanelMetrics.defaultWidth)
        #expect(panel.openWidth(in: 1400) == SidePanelMetrics.minWidth)
    }
}
