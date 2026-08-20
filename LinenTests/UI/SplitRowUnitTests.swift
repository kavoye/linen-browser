// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// The sidebar's grid row as one thing: off screen it hovers and clicks as a
/// unit, on screen its cells answer for themselves.
struct SplitRowInteractionTests {
    @Test func aRowOffScreenAnswersAsOneThing() {
        #expect(SplitRowInteraction.mode(isOnScreen: false) == .wholeRow)
    }

    @Test func aRowOnScreenAnswersPaneByPane() {
        #expect(SplitRowInteraction.mode(isOnScreen: true) == .perPane)
    }

    @Test func aClickOnTheWholeRowOpensTheLeadingPage() {
        let clicked = UUID()
        let leader = UUID()
        #expect(
            SplitRowInteraction.activationTarget(clicked: clicked, leader: leader, mode: .wholeRow)
                == leader
        )
    }

    @Test func aClickOnAShowingRowFocusesTheClickedPane() {
        let clicked = UUID()
        let leader = UUID()
        #expect(
            SplitRowInteraction.activationTarget(clicked: clicked, leader: leader, mode: .perPane)
                == clicked
        )
    }
}

/// Opening a grid is opening all of its pages: activation must wake every
/// deferred pane, not only the one the click named.
@MainActor
struct SplitRowActivationTests {
    private func makeModel() -> BrowserModel {
        BrowserModel(
            database: .temporary(),
            sitePermissions: SitePermissions(
                storageURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("SplitRowActivation-\(UUID().uuidString).json")
            )
        )
    }

    @Test func openingAColdSplitWakesEveryPane() {
        let model = makeModel()
        let other = model.newTab(url: URL(string: "https://example.com/c"))
        let left = model.newTab(url: URL(string: "https://example.com/a"))
        let right = model.newTab(url: URL(string: "https://example.com/b"))
        model.split(left, with: right, axis: .sideBySide)
        model.activate(other)

        left.deferRestore(state: nil, url: URL(string: "https://example.com/a"))
        right.deferRestore(state: nil, url: URL(string: "https://example.com/b"))
        #expect(left.isDeferred)
        #expect(right.isDeferred)

        model.activate(left)

        #expect(!left.isDeferred)
        #expect(!right.isDeferred)
    }

    @Test func openingAColdSplitByEitherPaneWakesBoth() {
        let model = makeModel()
        let other = model.newTab(url: URL(string: "https://example.com/c"))
        let left = model.newTab(url: URL(string: "https://example.com/a"))
        let right = model.newTab(url: URL(string: "https://example.com/b"))
        model.split(left, with: right, axis: .stacked)
        model.activate(other)

        left.deferRestore(state: nil, url: URL(string: "https://example.com/a"))
        right.deferRestore(state: nil, url: URL(string: "https://example.com/b"))

        model.activate(right)

        #expect(!left.isDeferred)
        #expect(!right.isDeferred)
    }

    @Test func openingALoneTabLeavesOtherTabsAsleep() {
        let model = makeModel()
        let awake = model.newTab(url: URL(string: "https://example.com/a"))
        let asleep = model.newTab(url: URL(string: "https://example.com/b"))
        model.activate(asleep)
        asleep.deferRestore(state: nil, url: URL(string: "https://example.com/b"))

        model.activate(awake)

        #expect(asleep.isDeferred)
    }
}
