// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// A pinned tab is the one you meant to keep, so a new tab opens under it
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

    private func pin(_ tab: BrowserTab, _ address: String, in model: BrowserModel) {
        tab.urlString = address
        model.pin(tab)
    }

    @Test func aNewTabOpensUnderThePinnedOnes() {
        let model = model()
        let kept = model.newTab(url: URL(string: "https://kept.example/"))
        pin(kept, "https://kept.example/", in: model)

        let fresh = model.newTab(url: URL(string: "https://fresh.example/"))
        fresh.urlString = "https://fresh.example/"

        #expect(order(model) == ["https://kept.example/", "https://fresh.example/"])
    }

    @Test func everyPinnedTabKeepsItsPlace() {
        let model = model()
        let first = model.newTab(url: URL(string: "https://one.example/"))
        pin(first, "https://one.example/", in: model)
        let second = model.newTab(url: URL(string: "https://two.example/"))
        pin(second, "https://two.example/", in: model)

        let fresh = model.newTab(url: URL(string: "https://fresh.example/"))
        fresh.urlString = "https://fresh.example/"

        let addresses = order(model)
        #expect(addresses.last == "https://fresh.example/")
        #expect(addresses.count == 3)
    }

    /// The report this rule came from: a link opened from a pinned tab
    /// landed right under its opener, splitting the pinned run and making
    /// the tabs pushed below the newcomer read as unpinned.
    @Test func aTabOpenedFromAPinnedTabLandsUnderTheLine() {
        let model = model()
        let first = model.newTab(url: URL(string: "https://one.example/"))
        pin(first, "https://one.example/", in: model)
        let second = model.newTab(url: URL(string: "https://two.example/"))
        pin(second, "https://two.example/", in: model)

        let fresh = model.newTab(url: URL(string: "https://fresh.example/"), after: first)
        fresh.urlString = "https://fresh.example/"

        #expect(order(model) == [
            "https://one.example/",
            "https://two.example/",
            "https://fresh.example/",
        ])
    }

    @Test func openingFromAPinLandsAboveTheLooseTabs() {
        let model = model()
        let kept = model.newTab(url: URL(string: "https://kept.example/"))
        pin(kept, "https://kept.example/", in: model)
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
        pin(kept, "https://kept.example/", in: model)
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

    /// Pinning lifts the tab into the pinned run, so the newcomer lands under
    /// the line rather than beside its opener.
    @Test func pinningATabLiftsItIntoThePinnedRun() {
        let model = model()
        let deep = model.newTab(url: URL(string: "https://deep.example/"))
        deep.urlString = "https://deep.example/"
        let loose = model.newTab(url: URL(string: "https://loose.example/"))
        loose.urlString = "https://loose.example/"
        model.pin(deep)

        let fresh = model.newTab(url: URL(string: "https://fresh.example/"), after: deep)
        fresh.urlString = "https://fresh.example/"

        #expect(order(model) == [
            "https://deep.example/",
            "https://fresh.example/",
            "https://loose.example/",
        ])
    }

    /// With nothing pinned, a new tab still opens at the top.
    @Test func aNewTabStillOpensFirstWhenNothingIsPinned() {
        let model = model()
        let older = model.newTab(url: URL(string: "https://older.example/"))
        older.urlString = "https://older.example/"

        let fresh = model.newTab(url: URL(string: "https://fresh.example/"))
        fresh.urlString = "https://fresh.example/"

        #expect(order(model).first == "https://fresh.example/")
    }

    /// Unpinning drops the tab out of the run, to the top of the loose tabs.
    @Test func unpinningDropsTheTabBelowTheLine() {
        let model = model()
        let first = model.newTab(url: URL(string: "https://one.example/"))
        pin(first, "https://one.example/", in: model)
        let second = model.newTab(url: URL(string: "https://two.example/"))
        pin(second, "https://two.example/", in: model)
        let loose = model.newTab(url: URL(string: "https://loose.example/"))
        loose.urlString = "https://loose.example/"

        model.unpin(first)

        #expect(order(model) == [
            "https://two.example/",
            "https://one.example/",
            "https://loose.example/",
        ])
    }
}
