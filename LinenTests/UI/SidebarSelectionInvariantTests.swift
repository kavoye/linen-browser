// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// One selection highlight, on the thing actually shown. Every row derives
/// its fill from `SidebarDestination` plus the marked rows, so this suite
/// drives the navigation matrix and checks that the destination is the
/// expected one and that no stale mark survives to light a second row.
@MainActor
@Suite(.serialized)
struct SidebarSelectionInvariantTests {
    private func makeModel() -> BrowserModel {
        BrowserModel(database: .temporary())
    }

    /// Exactly what the sidebar draws: the destination's row plus any marks.
    private func litRows(_ model: BrowserModel, page: AppCoordinator.Page = .browser) -> Set<SidebarItem> {
        var lit = model.sidebarSelection.items
        if case .tab(let id) = SidebarDestination.resolve(page: page, activeTabID: model.activeTab?.id) {
            lit.insert(.tab(id))
        }
        return lit
    }

    // MARK: - The resolver

    @Test func settingsOutranksTheActiveTab() {
        let id = UUID()
        #expect(SidebarDestination.resolve(page: .settings, activeTabID: id) == .settings)
        #expect(SidebarDestination.resolve(page: .browser, activeTabID: id) == .tab(id))
        #expect(SidebarDestination.resolve(page: .browser, activeTabID: nil) == nil)
    }

    // MARK: - ⌘T

    @Test func aNewTabIsTheOnlySelectedRow() {
        let model = makeModel()
        let first = model.newTab()
        model.sidebarSelection.anchor(on: .tab(first.id))
        model.activate(first)

        let second = model.newTab()
        #expect(litRows(model) == [.tab(second.id)])
    }

    @Test func aNewTabDropsMarkedRows() {
        let model = makeModel()
        let first = model.newTab()
        model.sidebarSelection.toggle(.tab(first.id))

        let second = model.newTab()
        #expect(model.sidebarSelection.isEmpty)
        #expect(litRows(model) == [.tab(second.id)])
    }

    // MARK: - The pin-return segment on another tab's row

    @Test func returningAnotherTabToItsPinSelectsThatTab() {
        let model = makeModel()
        let pinned = model.newTab()
        pinned.urlString = "https://pinned.example/"
        model.pin(pinned)
        pinned.urlString = "https://pinned.example/wandered"
        #expect(pinned.isAwayFromPin)

        let other = model.newTab()
        model.sidebarSelection.anchor(on: .tab(other.id))
        model.activate(other)

        model.returnToPin(pinned)
        #expect(model.activeTab === pinned)
        #expect(litRows(model) == [.tab(pinned.id)])
    }

    // MARK: - Settings

    @Test func settingsShowsNoTabAsSelected() {
        let model = makeModel()
        let tab = model.newTab()
        model.sidebarSelection.anchor(on: .tab(tab.id))
        model.activate(tab)

        #expect(SidebarDestination.resolve(page: .settings, activeTabID: model.activeTab?.id) == .settings)
        #expect(litRows(model, page: .settings) == [])
    }

    // MARK: - Clicks, marks and drags

    @Test func aPlainClickMarksNothing() {
        let model = makeModel()
        let first = model.newTab()
        _ = model.newTab()
        model.sidebarSelection.anchor(on: .tab(first.id))
        model.activate(first)

        #expect(model.sidebarSelection.isEmpty)
        #expect(litRows(model) == [.tab(first.id)])
    }

    @Test func marksAreTheOnlyWayTwoRowsLight() {
        let model = makeModel()
        let first = model.newTab()
        let second = model.newTab()
        model.sidebarSelection.toggle(.tab(first.id))

        #expect(litRows(model) == [.tab(first.id), .tab(second.id)])

        model.activate(first)
        #expect(model.sidebarSelection.isEmpty)
        #expect(litRows(model) == [.tab(first.id)])
    }

    @Test func aMarkStartsFromTheShownRow() {
        let model = makeModel()
        let first = model.newTab()
        let second = model.newTab()
        model.sidebarSelection.hold(.tab(second.id))
        model.sidebarSelection.toggle(.tab(first.id))

        #expect(model.sidebarSelection.items == [.tab(first.id), .tab(second.id)])
        #expect(litRows(model) == model.sidebarSelection.items)
    }

    @Test func theShownRowJoinsTheMarksOnlyWhileThereAreNone() {
        let model = makeModel()
        let first = model.newTab()
        let second = model.newTab()
        model.sidebarSelection.toggle(.tab(first.id))
        model.sidebarSelection.hold(.tab(second.id))

        #expect(model.sidebarSelection.items == [.tab(first.id)])
    }

    @Test func aShiftReachStillExtendsFromThePlainClick() {
        let model = makeModel()
        let first = model.newTab()
        let second = model.newTab()
        _ = model.newTab()

        model.sidebarSelection.anchor(on: .tab(second.id))
        model.activate(second)
        model.sidebarSelection.extend(to: .tab(first.id), in: model.sidebarTree) { _ in false }

        #expect(model.sidebarSelection.items == [.tab(second.id), .tab(first.id)])
    }

    @Test func aDragGrabOutsideTheMarksCarriesJustThatRow() {
        let model = makeModel()
        let first = model.newTab()
        let second = model.newTab()
        model.sidebarSelection.toggle(.tab(first.id))

        let carried = model.sidebarSelection.carried(startingOn: .tab(second.id), in: model.sidebarTree)
        #expect(carried == [.tab(second.id)])
        #expect(model.sidebarSelection.isEmpty)
    }

    // MARK: - Closing

    @Test func closingTheActiveTabLeavesOneSelectedRow() {
        let model = makeModel()
        let survivor = model.newTab()
        let doomed = model.newTab()
        model.sidebarSelection.toggle(.tab(survivor.id))

        model.close(doomed)
        #expect(model.sidebarSelection.isEmpty)
        #expect(litRows(model) == [.tab(survivor.id)])
    }

    @Test func closingAllTabsClearsEverything() {
        let model = makeModel()
        _ = model.newTab()
        let marked = model.newTab()
        model.sidebarSelection.toggle(.tab(marked.id))

        model.closeAllTabs()
        #expect(model.sidebarSelection.isEmpty)
        #expect(litRows(model) == [])
    }

    // MARK: - The browser's own pages

    @Test func theDownloadsPageIsTheOnlySelectedRow() {
        let model = makeModel()
        let origin = model.newTab()
        origin.urlString = "https://example.com/"
        model.sidebarSelection.toggle(.tab(origin.id))

        let downloads = model.showDownloads()
        #expect(downloads.internalPage == .downloads)
        #expect(litRows(model) == [.tab(downloads.id)])
    }

    /// The page can land in the already-active blank tab, where nothing about
    /// `activeTabID` changes - the marks still have to go.
    @Test func showingHistoryOverABlankTabDropsMarks() {
        let previous = BrowserSettings.shared.newTab
        BrowserSettings.shared.newTab = .startPage
        defer { BrowserSettings.shared.newTab = previous }

        let model = makeModel()
        let other = model.newTab()
        other.urlString = "https://example.com/"
        let blank = model.newTab()
        #expect(blank.urlString.isEmpty)
        model.sidebarSelection.toggle(.tab(other.id))

        let history = model.showHistory()
        #expect(history === blank)
        #expect(model.sidebarSelection.isEmpty)
        #expect(litRows(model) == [.tab(history.id)])
    }

    // MARK: - Restore

    @Test func aRestoredSessionSelectsOnlyTheActiveTab() {
        let previous = BrowserSettings.shared.startup
        BrowserSettings.shared.startup = .restore
        defer { BrowserSettings.shared.startup = previous }

        let database = AppDatabase.temporary()
        let first = BrowserModel(database: database)
        _ = first.newTab()
        let active = first.newTab()
        first.saveBlocking()

        let reopened = BrowserModel(database: database)
        reopened.restoreSession()
        #expect(reopened.sidebarSelection.isEmpty)
        #expect(litRows(reopened) == [.tab(active.id)])
    }
}
