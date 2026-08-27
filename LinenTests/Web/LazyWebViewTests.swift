// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// A restored tab is a row until you open it. Every sweep over `tabs` that
/// reaches for `webView` builds one, which is how a session of fourteen tabs
/// used to cost fourteen web views before the window could draw, so each of
/// those sweeps is held to the promise here.
@MainActor
struct LazyWebViewTests {
    private func session(tabs count: Int) -> AppDatabase {
        let database = AppDatabase.temporary()
        let model = BrowserModel(database: database)
        for index in 0..<count {
            model.newTab(url: URL(string: "https://\(index).example/"))
        }
        model.saveBlocking()
        return database
    }

    private func reopen(_ database: AppDatabase) -> BrowserModel {
        let model = BrowserModel(database: database)
        model.restoreSession()
        return model
    }

    @Test func restoringASessionBuildsAViewOnlyForTheTabOnScreen() {
        let reopened = reopen(session(tabs: 5))

        #expect(reopened.tabs.count == 5)
        let materialised = reopened.tabs.filter(\.isMaterialised)
        #expect(materialised.map(\.id) == [reopened.activeTabID].compactMap { $0 })
    }

    @Test func openingARestoredTabBuildsItsView() {
        let reopened = reopen(session(tabs: 3))
        let waiting = reopened.tabs.first { $0.id != reopened.activeTabID }

        #expect(waiting?.isMaterialised == false)
        reopened.activeTabID = waiting?.id

        #expect(waiting?.isMaterialised == true)
    }

    @Test func everyPaneOfARestoredSplitIsBuilt() {
        let database = AppDatabase.temporary()
        let model = BrowserModel(database: database)
        let left = model.newTab(url: URL(string: "https://a.example/"))
        let right = model.newTab(url: URL(string: "https://b.example/"))
        model.split(left, with: right, axis: .sideBySide)
        model.activeTabID = left.id
        model.saveBlocking()

        let reopened = reopen(database)
        let panes = reopened.activeSplit?.tabs.compactMap { reopened.tab(id: $0) } ?? []

        let builtPanes = panes.filter(\.isMaterialised).count
        #expect(panes.count == 2)
        #expect(builtPanes == 2)
    }

    @Test func writingTheSessionLeavesWaitingTabsAlone() {
        let reopened = reopen(session(tabs: 4))
        reopened.saveBlocking()

        #expect(reopened.tabs.filter(\.isMaterialised).count == 1)
    }

    @Test func applyingWebSettingsLeavesWaitingTabsAlone() {
        let reopened = reopen(session(tabs: 4))
        reopened.applyWebSettings()

        #expect(reopened.tabs.filter(\.isMaterialised).count == 1)
    }

    @Test func wipingTheSessionLeavesWaitingTabsAlone() {
        let reopened = reopen(session(tabs: 4))
        let waiting = reopened.tabs.filter { $0.id != reopened.activeTabID }
        reopened.closeAllTabs()

        let stillWaiting = waiting.filter { !$0.isMaterialised }.count
        let closed = waiting.filter(\.isClosed).count
        #expect(stillWaiting == waiting.count)
        #expect(closed == waiting.count)
    }

    @Test func closingAWaitingTabLeavesItAlone() {
        let reopened = reopen(session(tabs: 3))
        guard let waiting = reopened.tabs.first(where: { $0.id != reopened.activeTabID }) else {
            Issue.record("the session restored no tab to leave alone")
            return
        }
        reopened.close(waiting)

        #expect(!waiting.isMaterialised)
        #expect(waiting.isClosed)
        #expect(reopened.tabs.count == 2)
    }

    @Test func aTabWaitingToBeOpenedAnswersWithoutAView() {
        let reopened = reopen(session(tabs: 2))
        guard let waiting = reopened.tabs.first(where: { $0.id != reopened.activeTabID }) else {
            Issue.record("the session restored no tab to leave alone")
            return
        }

        #expect(!waiting.canGoBack)
        #expect(!waiting.canGoForward)
        #expect(waiting.backList.isEmpty)
        #expect(!waiting.isMaterialised)
    }

    /// A tab that has been shown keeps a view when it sleeps, and takes a
    /// fresh one: it is the page that is given up, not the view. Only a tab
    /// that has never been opened waits without one.
    @Test func aSleptTabTakesAFreshViewAndWaitsToLoad() {
        let model = BrowserModel(database: .temporary())
        let first = model.newTab(url: URL(string: "https://a.example/"))
        let second = model.newTab(url: URL(string: "https://b.example/"))
        model.activeTabID = second.id
        first.urlString = "https://a.example/"

        #expect(first.isMaterialised)
        let before = first.webView
        first.discardWebContent()

        #expect(first.isMaterialised, "a slept tab keeps a view to wake into")
        #expect(first.webView !== before, "the page it was showing is gone")
        #expect(first.isDeferred)
    }

    @Test func aSleptTabComesBackWhenItIsOpenedAgain() {
        let model = BrowserModel(database: .temporary())
        let first = model.newTab(url: URL(string: "https://a.example/"))
        let second = model.newTab(url: URL(string: "https://b.example/"))
        model.activeTabID = second.id
        first.urlString = "https://a.example/"
        first.discardWebContent()

        model.activeTabID = first.id

        #expect(first.isMaterialised)
        #expect(!first.isDeferred)
    }
}
