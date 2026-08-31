// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// A bookmarked tab is the one you meant to keep, so a new tab opens under it
/// rather than pushing it down the list.
@MainActor
struct KeptTabOrderTests {
    private func model() -> BrowserModel {
        BrowserModel(database: .temporary())
    }

    private func order(_ model: BrowserModel) -> [String] {
        model.rows(in: nil).compactMap { item in
            guard case .tab(let id) = item else { return nil }
            return model.tabs.first { $0.id == id }?.urlString
        }
    }

    private func bookmark(_ tab: BrowserTab, _ address: String, in model: BrowserModel) {
        tab.urlString = address
        model.pin(tab)
    }

    @Test func aNewTabOpensUnderTheBookmarkedOnes() {
        let model = model()
        let kept = model.newTab(url: URL(string: "https://kept.example/"))
        bookmark(kept, "https://kept.example/", in: model)

        let fresh = model.newTab(url: URL(string: "https://fresh.example/"))
        fresh.urlString = "https://fresh.example/"

        #expect(order(model) == ["https://kept.example/", "https://fresh.example/"])
    }

    @Test func everyBookmarkedTabKeepsItsPlace() {
        let model = model()
        let first = model.newTab(url: URL(string: "https://one.example/"))
        bookmark(first, "https://one.example/", in: model)
        let second = model.newTab(url: URL(string: "https://two.example/"))
        bookmark(second, "https://two.example/", in: model)

        let fresh = model.newTab(url: URL(string: "https://fresh.example/"))
        fresh.urlString = "https://fresh.example/"

        let addresses = order(model)
        #expect(addresses.last == "https://fresh.example/")
        #expect(addresses.count == 3)
    }

    /// The report this rule came from: a link opened from a bookmarked tab
    /// landed right under its opener, splitting the bookmarked run and making
    /// the tabs pushed below the newcomer read as unpinned.
    @Test func aTabOpenedFromABookmarkedTabLandsUnderTheLine() {
        let model = model()
        let first = model.newTab(url: URL(string: "https://one.example/"))
        bookmark(first, "https://one.example/", in: model)
        let second = model.newTab(url: URL(string: "https://two.example/"))
        bookmark(second, "https://two.example/", in: model)

        let fresh = model.newTab(url: URL(string: "https://fresh.example/"), after: first)
        fresh.urlString = "https://fresh.example/"

        #expect(order(model) == [
            "https://one.example/",
            "https://two.example/",
            "https://fresh.example/",
        ])
    }

    @Test func openingFromABookmarkLandsAboveTheLooseTabs() {
        let model = model()
        let kept = model.newTab(url: URL(string: "https://kept.example/"))
        bookmark(kept, "https://kept.example/", in: model)
        let loose = model.newTab(url: URL(string: "https://loose.example/"))
        loose.urlString = "https://loose.example/"

        let fresh = model.newTab(url: URL(string: "https://fresh.example/"), after: kept)
        fresh.urlString = "https://fresh.example/"

        #expect(order(model) == [
            "https://kept.example/",
            "https://fresh.example/",
            "https://loose.example/",
        ])
    }

    /// Below the line nothing changes: a tab opened from a loose tab still
    /// lands beside its opener.
    @Test func openingFromALooseTabStaysBesideIt() {
        let model = model()
        let kept = model.newTab(url: URL(string: "https://kept.example/"))
        bookmark(kept, "https://kept.example/", in: model)
        let older = model.newTab(url: URL(string: "https://older.example/"))
        older.urlString = "https://older.example/"
        let newer = model.newTab(url: URL(string: "https://newer.example/"))
        newer.urlString = "https://newer.example/"

        let fresh = model.newTab(url: URL(string: "https://fresh.example/"), after: newer)
        fresh.urlString = "https://fresh.example/"

        #expect(order(model) == [
            "https://kept.example/",
            "https://newer.example/",
            "https://fresh.example/",
            "https://older.example/",
        ])
    }

    /// A bookmark below the line is an ordinary opener; only the run at the
    /// top redirects newcomers.
    @Test func openingFromABookmarkOutsideTheTopRunStaysBesideIt() {
        let model = model()
        let deep = model.newTab(url: URL(string: "https://deep.example/"))
        deep.urlString = "https://deep.example/"
        let loose = model.newTab(url: URL(string: "https://loose.example/"))
        loose.urlString = "https://loose.example/"
        model.pin(deep)

        let fresh = model.newTab(url: URL(string: "https://fresh.example/"), after: deep)
        fresh.urlString = "https://fresh.example/"

        #expect(order(model) == [
            "https://loose.example/",
            "https://deep.example/",
            "https://fresh.example/",
        ])
    }

    /// With nothing bookmarked, a new tab still opens at the top.
    @Test func aNewTabStillOpensFirstWhenNothingIsBookmarked() {
        let model = model()
        let older = model.newTab(url: URL(string: "https://older.example/"))
        older.urlString = "https://older.example/"

        let fresh = model.newTab(url: URL(string: "https://fresh.example/"))
        fresh.urlString = "https://fresh.example/"

        #expect(order(model).first == "https://fresh.example/")
    }

    /// Only the run at the top holds a new tab back. A bookmark further down
    /// the list is not a lid over everything above it.
    @Test func onlyTheBookmarkedRunAtTheTopHoldsANewTabBack() {
        let model = model()
        let deep = model.newTab(url: URL(string: "https://deep.example/"))
        deep.urlString = "https://deep.example/"
        let loose = model.newTab(url: URL(string: "https://loose.example/"))
        loose.urlString = "https://loose.example/"
        model.pin(deep)

        let fresh = model.newTab(url: URL(string: "https://fresh.example/"))
        fresh.urlString = "https://fresh.example/"

        #expect(order(model) == [
            "https://fresh.example/",
            "https://loose.example/",
            "https://deep.example/",
        ])
    }
}
