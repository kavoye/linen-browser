// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

/// The tab list's lifecycle: what opens where, what closing takes with it,
/// and what ⇧⌘T brings back. Every model here saves to a database of the
/// test's own, so nothing can touch a real browsing session.
@MainActor
@Suite(.serialized, .boundedWebViews)
struct BrowserModelTests {
    private func makeModel() -> BrowserModel {
        BrowserModel(database: .temporary())
    }

    @Test func aNewTabLandsOnTopAndTakesFocus() {
        let model = makeModel()
        let first = model.newTab()
        let second = model.newTab()

        #expect(model.tabs.first === second)
        #expect(model.activeTab === second)
        #expect(model.tabs.count == 2)
        #expect(model.sidebarItems.first == .tab(second.id))
        _ = first
    }

    @Test func aBackgroundTabDoesNotStealFocus() {
        let model = makeModel()
        let front = model.newTab()
        _ = model.newTab(activate: false)

        #expect(model.activeTab === front)
    }

    @Test func closingTheActiveTabHandsFocusToTheTopmost() {
        let model = makeModel()
        let survivor = model.newTab()
        let doomed = model.newTab()

        model.close(doomed)
        #expect(model.activeTab === survivor)
        #expect(model.tabs.count == 1)
        #expect(!model.sidebarItems.contains(.tab(doomed.id)))
    }

    @Test func closingABackgroundTabLeavesFocusAlone() {
        let model = makeModel()
        let background = model.newTab()
        let front = model.newTab()

        model.close(background)
        #expect(model.activeTab === front)
    }

    /// ⇧⌘T's whole promise: the tab comes back where it sat, under its own
    /// name, and takes focus - not a fresh tab that happens to share a URL.
    @Test func reopenBringsATabBackWhereItWas() {
        let model = makeModel()
        let top = model.newTab()
        let middle = model.newTab(activate: false)
        let bottom = model.newTab(activate: false)
        // Insertion is newest-on-top, so the list reads bottom, middle, top.
        #expect(model.tabs.map(\.id) == [bottom.id, middle.id, top.id])

        middle.title = "The one that was closed"
        middle.urlString = "https://example.com/middle"
        model.close(middle)
        model.reopenLastClosedTab()

        #expect(model.tabs.count == 3)
        let reopened = model.tabs[1]
        #expect(reopened.title == "The one that was closed")
        #expect(reopened.urlString == "https://example.com/middle")
        #expect(model.activeTab === reopened)
        #expect(model.sidebarItems[1] == .tab(reopened.id))
    }

    @Test func reopenWithNothingClosedDoesNothing() {
        let model = makeModel()
        _ = model.newTab()

        #expect(!model.canReopenClosedTab)
        model.reopenLastClosedTab()
        #expect(model.tabs.count == 1)
    }

    @Test func aRolledBackTabIsNotAddedToRecentlyClosed() {
        let model = makeModel()
        let tab = model.newTab()

        model.close(tab, recordForReopening: false)

        #expect(!model.canReopenClosedTab)
        #expect(model.tabs.isEmpty)
    }

    @Test func pinningAnchorsThePageAndSurvivesDuplication() {
        let model = makeModel()
        let tab = model.newTab()
        tab.urlString = "https://example.com/docs"
        tab.title = "Docs"

        model.pin(tab)
        #expect(tab.pinnedURL?.absoluteString == "https://example.com/docs")
        #expect(tab.pinnedTitle == "Docs")

        let copy = model.duplicate(tab)
        #expect(copy.pinnedURL == tab.pinnedURL)
        #expect(model.activeTab === copy)

        model.unpin(tab)
        #expect(tab.pinnedURL == nil)
        #expect(copy.pinnedURL != nil)
    }

    /// "Pin this" needs a page to mean; an empty tab has none to offer.
    @Test func pinningAnEmptyTabRefuses() {
        let model = makeModel()
        let tab = model.newTab()

        model.pin(tab)
        #expect(tab.pinnedURL == nil)
    }

    @Test func aFolderGathersTabsAndDeletionFreesThemInPlace() {
        let model = makeModel()
        let a = model.newTab()
        let b = model.newTab()

        // Named explicitly so the on-device auto-namer never runs and the
        // test can't race a suggestion arriving mid-assertion.
        let folder = model.createFolder(named: "Trip", containing: [a, b])
        #expect(Set(model.tabs(in: folder).map(\.id)) == [a.id, b.id])
        #expect(model.folder(containing: a) === folder)
        #expect(!model.sidebarItems.contains(.tab(a.id)))
        #expect(model.sidebarItems.contains(.folder(folder.id)))

        model.deleteFolder(folder)
        #expect(model.folders.isEmpty)
        #expect(model.folder(containing: a) == nil)
        #expect(model.sidebarItems.contains(.tab(a.id)))
        #expect(model.sidebarItems.contains(.tab(b.id)))
    }

    @Test func movingATabOutOfItsFolderReturnsItToTheTopLevel() {
        let model = makeModel()
        let a = model.newTab()
        let b = model.newTab()
        let folder = model.createFolder(named: "Work", containing: [a, b])

        model.move(a, to: nil)
        #expect(model.folder(containing: a) == nil)
        #expect(model.sidebarItems.contains(.tab(a.id)))
        #expect(model.folder(containing: b) === folder)
    }

    @Test func closingAFolderedTabAlsoLeavesTheFolder() {
        let model = makeModel()
        let a = model.newTab()
        let folder = model.createFolder(named: "Solo", containing: [a])

        model.close(a)
        #expect(model.tabs(in: folder).isEmpty)
        #expect(model.rows(in: folder).isEmpty)
    }

    // MARK: - Nesting and batch moves

    @Test func aFolderCanBeMovedIntoAnotherFolder() {
        let model = makeModel()
        let a = model.newTab()
        let b = model.newTab()
        let inner = model.createFolder(named: "Inner", containing: [a])
        let outer = model.createFolder(named: "Outer", containing: [b])

        model.move([.folder(inner.id)], into: outer)
        #expect(model.folder(containing: inner) === outer)
        #expect(model.rows(in: outer).contains(.folder(inner.id)))
        #expect(model.folder(containing: a) === inner)
        #expect(model.tabs(in: outer).map(\.id) == [b.id])
        #expect(Set(model.allTabs(in: outer).map(\.id)) == [a.id, b.id])
        #expect(!model.sidebarItems.contains(.folder(inner.id)))
    }

    /// The one arrangement that would lose rows: everything under the folder
    /// would be reachable only from inside itself.
    @Test func aFolderRefusesToBeMovedIntoItsOwnContents() {
        let model = makeModel()
        let outer = model.createFolder(named: "Outer")
        let inner = model.createFolder(named: "Inner")
        model.move([.folder(inner.id)], into: outer)

        model.move([.folder(outer.id)], into: inner)
        #expect(model.folder(containing: outer) == nil)
        #expect(model.folder(containing: inner) === outer)
    }

    @Test func manyRowsMoveAtOnceAndKeepTheirOrder() {
        let model = makeModel()
        // Newest first, so the sidebar reads c, b, a downwards.
        let a = model.newTab()
        let b = model.newTab()
        let c = model.newTab()
        let folder = model.createFolder(named: "Reading")

        model.move([.tab(c.id), .tab(a.id)], into: folder)
        #expect(model.tabs(in: folder).map(\.id) == [c.id, a.id])
        #expect(model.folder(containing: b) == nil)
    }

    /// ⌃Tab walks this order, so it has to agree with what is on screen.
    @Test func nestedRowsReadTopToBottom() {
        let model = makeModel()
        let deep = model.newTab()
        let middle = model.newTab()
        let loose = model.newTab()
        let inner = model.createFolder(named: "Inner", containing: [deep])
        let outer = model.createFolder(named: "Outer", containing: [middle])
        model.move([.folder(inner.id)], into: outer, before: .tab(middle.id))
        model.move([.folder(outer.id)], into: nil, before: .tab(loose.id))

        #expect(model.tabs.map(\.id) == [deep.id, middle.id, loose.id])
    }

    @Test func deletingAFolderSpillsWhatItHeldIncludingFolders() {
        let model = makeModel()
        let a = model.newTab()
        let inner = model.createFolder(named: "Inner", containing: [a])
        let outer = model.createFolder(named: "Outer")
        model.move([.folder(inner.id)], into: outer)

        model.deleteFolder(outer)
        #expect(model.sidebarItems.contains(.folder(inner.id)))
        #expect(model.folder(containing: a) === inner)
    }

    @Test func closingASelectionTakesTheTabsInsideItsFolders() {
        let model = makeModel()
        let held = model.newTab()
        let loose = model.newTab()
        let survivor = model.newTab()
        let folder = model.createFolder(named: "Going", containing: [held])

        let selection: [SidebarItem] = [.folder(folder.id), .tab(loose.id)]
        #expect(model.tabCount(in: selection) == 2)
        model.close(selection)

        #expect(model.tabs.map(\.id) == [survivor.id])
        #expect(model.folders.isEmpty)
    }

    @Test func renamingAFolderRefusesEmptiness() {
        let model = makeModel()
        let folder = model.createFolder(named: "Named")

        model.renameFolder(folder, to: "   ")
        #expect(folder.name == "Named")
        model.renameFolder(folder, to: " Better ")
        #expect(folder.name == "Better")
    }

    /// ⌘1…⌘9: positions clamp to what exists rather than crashing or
    /// wrapping.
    @Test func tabShortcutsPickByPositionAndIgnoreTheVoid() {
        let model = makeModel()
        let older = model.newTab()
        let newer = model.newTab()

        model.activateTab(at: 1)
        #expect(model.activeTab === older)
        model.activateTab(at: 99)
        #expect(model.activeTab === older)
        model.activateLastTab()
        #expect(model.activeTab === older)
        model.activateTab(at: 0)
        #expect(model.activeTab === newer)
    }

    // MARK: - What a restored tab costs before it is opened

    /// A restored tab holds a view that has never loaded, and such a view has
    /// no WebContent process behind it - the whole of the saving, and
    /// invisible from anywhere else: warm and cold views are the same class,
    /// configured the same, differing only in whether anything was put in
    /// them. `url` is how that shows in-process.
    @Test func aRestoredTabsViewHasNeverLoaded() {
        let restored = BrowserTab(restoring: true)

        #expect(restored.webView.url == nil)
        #expect(restored.webView.backForwardList.currentItem == nil)
    }

    @Test func aLargeImportStaysDeferredUntilOpened() {
        let model = makeModel()
        let entries = (0..<100).map { index in
            HistoryStore.Entry(
                url: "https://fixture-\(index).example/",
                title: "Fixture \(index)",
                lastVisit: Date(timeIntervalSinceReferenceDate: Double(index))
            )
        }

        let folder = model.importBookmarksFolder(named: "Imported", entries: entries)
        let allDeferred = model.tabs.allSatisfy(\.isDeferred)
        let allUnloaded = model.tabs.allSatisfy { $0.webView.url == nil }
        let allWithoutHistory = model.tabs.allSatisfy {
            $0.webView.backForwardList.currentItem == nil
        }

        #expect(folder != nil)
        #expect(model.tabs.count == 100)
        #expect(allDeferred)
        #expect(allUnloaded)
        #expect(allWithoutHistory)
        model.cancelPendingSave()
    }

    /// The counterpart: a tab someone asked for takes a pooled view, and what
    /// it arrives holding is `WebViewPool.warmsPooledViews`'s to say. Written
    /// against the flag rather than one of its settings, so flipping it to
    /// compare arrangements can't leave this asserting the wrong one.
    @Test func aTabSomeoneAskedForTakesAPooledView() {
        let opened = BrowserTab()

        if WebViewPool.warmsPooledViews {
            // Sent the warm-up page at construction. It may still be in
            // flight - what matters is that it was given something to load,
            // which is what starts the process.
            #expect(opened.webView.url != nil || opened.webView.isLoading)
        } else {
            // The pool holds the views, WebKit holds the spare process, and
            // nothing loads until there is a page.
            #expect(opened.webView.url == nil)
        }
    }
}
