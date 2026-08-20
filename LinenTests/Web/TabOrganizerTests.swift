// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// The pure half of tab organizing: what survives of the model's grouping
/// once it meets the actual tab list. The model itself can't be asked for a
/// fixed answer, so `propose` stays untested and `plan` carries the rules.
@MainActor
struct TabOrganizerTests {
    private let tabs: [(id: UUID, title: String)] = (1...6).map { number in
        (UUID(), "Tab \(number)")
    }

    @Test func aPlanKeepsSidebarOrderAndDropsUnknownNumbers() {
        let plan = TabOrganizer.plan(
            from: [("Research", [5, 2, 99, 2, 0])],
            tabs: tabs
        )
        #expect(plan.folders.count == 1)
        #expect(plan.folders.first?.name == "Research")
        #expect(plan.folders.first?.tabIDs == [tabs[1].id, tabs[4].id])
    }

    @Test func aTabClaimedTwiceStaysWithItsFirstGroup() {
        let plan = TabOrganizer.plan(
            from: [("First", [1, 2]), ("Second", [2, 3])],
            tabs: tabs
        )
        #expect(plan.folders.count == 1)
        #expect(plan.folders.first?.name == "First")
    }

    @Test func aGroupLeftWithOneTabDissolves() {
        let plan = TabOrganizer.plan(
            from: [("Lonely", [4]), ("Pair", [1, 6])],
            tabs: tabs
        )
        #expect(plan.folders.map(\.name) == ["Pair"])
    }

    @Test func aShoutedOrJunkNameFallsBackCleanly() {
        let plan = TabOrganizer.plan(
            from: [("TRAVEL PLANNING", [1, 2]), ("\"..\"", [3, 4])],
            tabs: tabs
        )
        #expect(plan.folders.map(\.name) == ["Travel Planning", "New Folder"])
    }

    @Test func groupLinesParseBackIntoNamesAndNumbers() {
        let parsed = TabOrganizer.groups(in: [
            "Trip Planning: 2, 5",
            "Docs: 1,3 ,4",
            "Nameless 1, 2",
            ": 1, 2",
            "Lonely: 3",
            "Re: search: 5, 6",
        ])
        #expect(parsed.map(\.name) == ["Trip Planning", "Docs", "Re: search"])
        #expect(parsed.map(\.numbers) == [[2, 5], [1, 3, 4], [5, 6]])
    }

    @Test func nothingUsableMeansAnEmptyPlan() {
        let plan = TabOrganizer.plan(from: [("Ghosts", [40, 50])], tabs: tabs)
        #expect(plan.folders.isEmpty)
    }

    /// The apply half of organizing, minus the model: the folders a plan
    /// names must actually contain their tabs afterwards.
    @Test func applyingAPlanPutsTheTabsInTheirFolders() {
        let browser = BrowserModel(database: .temporary())
        let open = (1...5).map { number in
            let tab = browser.newTab()
            tab.title = "Tab \(number)"
            return tab
        }

        let plan = TabOrganizer.plan(
            from: [("Pets", [1, 2]), ("Work", [3, 4])],
            tabs: open.map { ($0.id, $0.title) }
        )
        for planned in plan.folders {
            let members = planned.tabIDs.compactMap { id in browser.tabs.first { $0.id == id } }
            browser.createFolder(named: planned.name, containing: members)
        }

        let pets = browser.folders.first { $0.name == "Pets" }
        let work = browser.folders.first { $0.name == "Work" }
        #expect(pets.map { browser.tabs(in: $0).map(\.id) } == [open[0].id, open[1].id])
        #expect(work.map { browser.tabs(in: $0).map(\.id) } == [open[2].id, open[3].id])
        #expect(browser.folder(containing: open[4]) == nil)
    }
}
