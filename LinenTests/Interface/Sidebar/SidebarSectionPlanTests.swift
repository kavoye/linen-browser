// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

struct SidebarSectionPlanTests {
    private let a = SidebarItem.tab(UUID())
    private let b = SidebarItem.tab(UUID())
    private let c = SidebarItem.tab(UUID())
    private let folder = SidebarItem.folder(UUID())

    private func plan(
        _ rows: [SidebarSectionPlan.Row],
        wasKept: Bool = false
    ) -> SidebarSectionPlan {
        SidebarSectionPlan(rows: rows, wasKept: wasKept)
    }

    private func kept(_ item: SidebarItem, carried: Bool = false) -> SidebarSectionPlan.Row {
        .init(item: item, isKept: true, isCarried: carried)
    }

    private func loose(_ item: SidebarItem, carried: Bool = false) -> SidebarSectionPlan.Row {
        .init(item: item, isKept: false, isCarried: carried)
    }

    // MARK: - Where the seam falls

    @Test func theSeamFallsAfterTheLeadingKeptRows() {
        #expect(plan([kept(a), kept(b), loose(c)]).cut(pinsCarried: false) == 2)
    }

    @Test func aLooseListHasNoSeam() {
        #expect(plan([loose(a), loose(b)]).cut(pinsCarried: false) == 0)
    }

    @Test func aListThatIsAllKeptHasNothingToSeparate() {
        #expect(plan([kept(a), kept(b)]).cut(pinsCarried: false) == 0)
    }

    @Test func aKeptRowBelowTheRunIsNotPartOfIt() {
        #expect(plan([kept(a), loose(b), kept(c)]).cut(pinsCarried: false) == 1)
    }

    // MARK: - Rows in the air

    @Test func aRowInTheAirHoldsItsPlaceWhileKeptRowsFollowIt() {
        let carried = plan([kept(a), loose(b, carried: true), kept(c), loose(a)])
        #expect(carried.cut(pinsCarried: true) == 3)
        #expect(carried.cut(pinsCarried: false) == 3)
    }

    @Test func aRowAtTheEdgeOfTheRunFollowsTheDrop() {
        let edge = plan([kept(a), loose(b, carried: true), loose(c)])
        #expect(edge.cut(pinsCarried: true) == 2)
        #expect(edge.cut(pinsCarried: false) == 1)
    }

    @Test func theOnlyMemberOfTheSectionStaysInItWhileItIsCarried() {
        let alone = plan([kept(folder, carried: true), loose(a), loose(b)], wasKept: true)
        #expect(alone.cut(pinsCarried: true) == 1)
        #expect(alone.cut(pinsCarried: false) == 0)
    }

    // MARK: - Which side a drop lands on

    @Test func landingBesideAKeptRowJoinsTheSection() {
        let list = plan([kept(a), loose(b)])
        #expect(list.lands(before: true, of: a))
        #expect(list.lands(before: false, of: a))
    }

    @Test func landingBesideALooseRowLeavesTheSection() {
        let list = plan([kept(a), loose(b)])
        #expect(!list.lands(before: true, of: b))
        #expect(!list.lands(before: false, of: b))
    }

    @Test func landingAboveEverythingKeepsARowThatWasKept() {
        let alone = plan([kept(folder, carried: true), loose(a), loose(b)], wasKept: true)
        #expect(alone.lands(before: true, of: a))
        #expect(!alone.lands(before: false, of: a))
        #expect(!alone.lands(before: true, of: b))
    }

    @Test func landingAboveEverythingDoesNotPinARowThatWasNotKept() {
        let list = plan([loose(a), loose(b, carried: true)], wasKept: false)
        #expect(!list.lands(before: true, of: a))
    }

    @Test func anAnchorTheRootDoesNotHoldAnswersForNoSection() {
        #expect(!plan([kept(a)]).lands(before: true, of: c))
    }
}
