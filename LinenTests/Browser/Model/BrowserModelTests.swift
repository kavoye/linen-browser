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

    @Test func closingTheActiveTabHandsFocusToTheOneBelowIt() {
        let model = makeModel()
        let survivor = model.newTab()
        let doomed = model.newTab()

        model.close(doomed)
        #expect(model.activeTab === survivor)
        #expect(model.tabs.count == 1)
        #expect(!model.sidebarItems.contains(.tab(doomed.id)))
    }

    @Test func closingTheLastTabInTheListFallsBackUpwards() {
        let model = makeModel()
        let bottom = model.newTab()
        let middle = model.newTab(activate: false)
        let top = model.newTab(activate: false)
        #expect(model.tabs.map(\.id) == [top.id, middle.id, bottom.id])

        model.activate(middle)
        model.close(middle)
        #expect(model.activeTab === bottom)

        model.close(bottom)
        #expect(model.activeTab === top)
    }

    @Test func aLinkOpenedFromATabLandsRightBelowIt() {
        let model = makeModel()
        let opener = model.newTab()
        let top = model.newTab()
        #expect(model.tabs.map(\.id) == [top.id, opener.id])

        opener.events.onOpenInNewTab?(URL(string: "https://example.com/linked")!, false)

        #expect(model.tabs.count == 3)
        #expect(model.tabs[1] === opener)
        let opened = model.tabs[2]
        #expect(model.sidebarItems == [.tab(top.id), .tab(opener.id), .tab(opened.id)])
        #expect(model.activeTab === top)
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

    /// A new tab is the Start page, and pins as one.
    @Test func pinningANewTabPinsTheStartPage() {
        let model = makeModel()
        let tab = model.newTab()

        model.pin(tab)
        #expect(tab.pinnedURL == SystemPages.start)
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
            // The pool holds the views and WebKit holds the spare process. The
            // only thing a blank tab loads is its own start page.
            #expect(opened.webView.url == nil || opened.webView.url == SystemPages.start)
        }
    }

    @Test func aTitleSetAfterLoadReachesHistory() {
        let model = makeModel()
        let tab = model.newTab()
        tab.urlString = "https://jira.example/browse/ENEY-6039"
        tab.title = "Jira"
        tab.events.onNavigationFinished?(false)

        tab.title = "[ENEY-6039] Tour cards stay on top - Jira"
        tab.events.onTitleChanged?()

        #expect(model.history.entries.first?.title == "[ENEY-6039] Tour cards stay on top - Jira")
    }

    @Test func aTitleAfterAnInPageMoveKeepsTheLoadedPageName() {
        let model = makeModel()
        let tab = model.newTab()
        tab.urlString = "https://jira.example/browse/ENEY-6039"
        tab.title = "[ENEY-6039] Tour cards stay on top - Jira"
        tab.events.onNavigationFinished?(false)

        tab.urlString = "https://jira.example/jira/your-work"
        tab.title = "Your work - Jira"
        tab.events.onTitleChanged?()

        #expect(model.history.entries.map(\.title) == ["[ENEY-6039] Tour cards stay on top - Jira"])
    }

    @Test func anInPageMoveIsAVisitOfItsOwn() async throws {
        let server = try await HTTPFixtureServer.start(routes: [
            "/board": .html("<!doctype html><title>Board - Jira</title><p>Board</p>"),
        ])
        defer { withExtendedLifetime(server) {} }
        let board = try server.url("/board")
        let ticket = try server.url("/browse/ENEY-6039")
        let model = makeModel()
        let tab = model.newTab(url: board)
        #expect(await settled(tab, at: board))
        #expect(await waitUntil { model.history.visits.count == 1 })

        _ = try await tab.webView.evaluateJavaScript("""
            history.pushState({}, '', '/browse/ENEY-6039');
            document.title = '[ENEY-6039] Tour cards stay on top - Jira';
            """)

        #expect(await waitUntil { model.history.visits.first?.title == "[ENEY-6039] Tour cards stay on top - Jira" })
        #expect(model.history.visits.map(\.url) == [ticket.absoluteString, board.absoluteString])
        #expect(model.history.visits.first?.transition == .inPage)
        #expect(model.history.entries.first { $0.url == board.absoluteString }?.title == "Board - Jira")
    }

    @Test func anAnchorJumpIsNotAVisit() async throws {
        let server = try await HTTPFixtureServer.start(routes: [
            "/docs": .html("<!doctype html><title>Docs</title><p id=\"usage\">Usage</p>"),
        ])
        defer { withExtendedLifetime(server) {} }
        let docs = try server.url("/docs")
        let model = makeModel()
        let tab = model.newTab(url: docs)
        #expect(await settled(tab, at: docs))
        #expect(await waitUntil { model.history.visits.count == 1 })

        _ = try await tab.webView.evaluateJavaScript("location.hash = 'usage'")
        #expect(await waitUntil { tab.urlString.hasSuffix("#usage") })

        #expect(model.history.visits.count == 1)
    }

    @Test func aFullLoadIsStillOneVisit() async throws {
        let server = try await HTTPFixtureServer.start(routes: [
            "/a": .html("<!doctype html><title>A</title><p>A</p>"),
            "/b": .html("<!doctype html><title>B</title><p>B</p>"),
        ])
        defer { withExtendedLifetime(server) {} }
        let a = try server.url("/a")
        let b = try server.url("/b")
        let model = makeModel()
        let tab = model.newTab(url: a)
        #expect(await settled(tab, at: a))

        tab.load(b)
        #expect(await settled(tab, at: b))
        #expect(await waitUntil { model.history.visits.first?.url == b.absoluteString })

        #expect(model.history.visits.map(\.url) == [b.absoluteString, a.absoluteString])
    }

    @Test(arguments: ["A", "B"])
    func anAddressChangeWhileLoadingBelongsToTheLoad(title: String) async throws {
        let image = ResponseGate()
        defer { image.open() }
        let server = try await HTTPFixtureServer.start(routes: [
            "/a": .html("<!doctype html><title>A</title><p>A</p>"),
            "/b": .html("""
                <!doctype html><title>\(title)</title>
                <script>history.replaceState({}, '', '/b?ready')</script>
                <img src="/slow">
                """),
            "/slow": .html("", gate: image),
        ])
        defer { withExtendedLifetime(server) {} }
        let a = try server.url("/a")
        var other = try #require(URLComponents(url: try server.url("/b?ready"), resolvingAgainstBaseURL: false))
        other.host = "localhost"
        let ready = try #require(other.url)
        let model = makeModel()
        let tab = model.newTab(url: a)
        #expect(await settled(tab, at: a))
        #expect(await waitUntil { model.history.visits.count == 1 })

        other.query = nil
        tab.load(try #require(other.url))
        #expect(await waitUntil { tab.urlString == ready.absoluteString })
        _ = try await tab.webView.evaluateJavaScript("document.title = 'Loaded'")
        #expect(await waitUntil { tab.title == "Loaded" })
        image.open()
        #expect(await settled(tab, at: ready))
        #expect(await waitUntil { model.history.visits.first?.url == ready.absoluteString })

        let visits = model.history.visits
        #expect(visits.map(\.url) == [ready.absoluteString, a.absoluteString])
        #expect(visits.map(\.transition) == [.typed, .typed])
        #expect(visits.first?.trail != visits.last?.trail)
    }

    @Test func anInPageMoveDuringASlowLoadIsKept() async throws {
        let image = ResponseGate()
        defer { image.open() }
        let server = try await HTTPFixtureServer.start(routes: [
            "/board": .html("<!doctype html><title>Board</title><img src=\"/slow\">"),
            "/slow": .html("", gate: image),
        ])
        defer { withExtendedLifetime(server) {} }
        let first = try server.url("/browse/1")
        let second = try server.url("/browse/2")
        let model = makeModel()
        let tab = model.newTab(url: try server.url("/board"))
        let recordFinish = tab.events.onNavigationFinished
        var finished = false
        tab.events.onNavigationFinished = { wasRestore in
            recordFinish?(wasRestore)
            finished = true
        }
        #expect(await waitUntil { tab.title == "Board" })

        _ = try await tab.webView.evaluateJavaScript("""
            history.pushState({}, '', '/browse/1');
            document.title = 'Ticket 1';
            """)
        #expect(await waitUntil { model.history.visits.first?.url == first.absoluteString })
        image.open()
        #expect(await waitUntil { finished })

        _ = try await tab.webView.evaluateJavaScript("""
            history.pushState({}, '', '/browse/2');
            document.title = 'Ticket 2';
            """)
        #expect(await waitUntil { model.history.visits.first?.url == second.absoluteString })

        let visits = model.history.visits
        #expect(visits.map(\.url) == [second.absoluteString, first.absoluteString])
        #expect(visits.map(\.transition) == [.inPage, .typed])
        #expect(Set(visits.map(\.trail)).count == 1)
    }

    @Test func aStoppedLoadLeavesInPageMovesAsVisits() async throws {
        let gate = ResponseGate()
        defer { gate.open() }
        let server = try await HTTPFixtureServer.start(routes: [
            "/a": .html("<!doctype html><title>A</title><p>A</p>"),
            "/b": .html("<!doctype html><title>B</title><p>B</p>", gate: gate),
        ])
        defer { withExtendedLifetime(server) {} }
        let a = try server.url("/a")
        let moved = try server.url("/a2")
        let model = makeModel()
        let tab = model.newTab(url: a)
        #expect(await settled(tab, at: a))
        #expect(await waitUntil { model.history.visits.count == 1 })

        tab.load(try server.url("/b"))
        #expect(await gate.waitForRequest())
        tab.webView.stopLoading()
        #expect(await waitUntil { !tab.awaitsVisit })

        _ = try await tab.webView.evaluateJavaScript("""
            history.pushState({}, '', '/a2');
            document.title = 'A2';
            """)
        #expect(await waitUntil { model.history.visits.first?.url == moved.absoluteString })

        let visits = model.history.visits
        #expect(visits.map(\.transition) == [.inPage, .typed])
        #expect(Set(visits.map(\.trail)).count == 1)
    }

    private func visit(_ tab: BrowserTab, _ url: String, _ transition: HistoryStore.Transition = .link) {
        tab.noteTransition(transition)
        tab.urlString = url
        tab.title = url
        tab.events.onNavigationFinished?(false)
    }

    @Test func aTabsJourneyIsOneTrail() {
        let model = makeModel()
        let tab = model.newTab()
        visit(tab, "https://jira.example/board", .typed)
        visit(tab, "https://jira.example/browse/1")
        visit(tab, "https://jira.example/browse/1", .reload)
        visit(tab, "https://docs.example/spec")

        #expect(Set(model.history.visits.map(\.trail)).count == 1)
    }

    @Test func aNewTabStartsANewTrail() {
        let model = makeModel()
        let first = model.newTab()
        visit(first, "https://jira.example/board", .typed)
        let second = model.newTab()
        visit(second, "https://jira.example/board", .typed)
        visit(first, "https://jira.example/browse/1")

        let trails = model.history.visits.map(\.trail)
        #expect(trails[0] == trails[2])
        #expect(trails[1] != trails[0])
    }

    @Test func typingAnotherSiteStartsANewTrail() {
        let model = makeModel()
        let tab = model.newTab()
        visit(tab, "https://jira.example/board", .typed)
        visit(tab, "https://www.jira.example/browse/1", .typed)
        visit(tab, "https://twitch.example/", .typed)

        let trails = model.history.visits.map(\.trail)
        #expect(trails[1] == trails[2], "the same site typed again keeps the trail")
        #expect(trails[0] != trails[1])
    }

    @Test func anInPageMoveWithTheSameTitleAddsNoRow() {
        let model = makeModel()
        let tab = model.newTab()
        visit(tab, "https://duckduckgo.com/?q=martian", .typed)
        tab.title = "martian at DuckDuckGo"
        tab.events.onTitleChanged?()

        tab.urlString = "https://duckduckgo.com/?q=martian&ia=images"
        tab.events.onInPageMove?()
        tab.urlString = "https://duckduckgo.com/?q=martian&ia=web"
        tab.events.onInPageMove?()
        tab.events.onTitleChanged?()

        #expect(model.history.visits.count == 1)
    }

    @Test func anInPageMoveCountsOnceItsTitleArrives() {
        let model = makeModel()
        let tab = model.newTab()
        visit(tab, "https://jira.example/board", .typed)
        tab.title = "Board - Jira"
        tab.events.onTitleChanged?()

        tab.urlString = "https://jira.example/browse/ENEY-6039"
        tab.events.onInPageMove?()
        #expect(model.history.visits.count == 1)

        tab.title = "[ENEY-6039] Tour cards stay on top - Jira"
        tab.events.onTitleChanged?()

        #expect(model.history.visits.map(\.url) == ["https://jira.example/browse/ENEY-6039", "https://jira.example/board"])
        #expect(model.history.visits.first?.title == "[ENEY-6039] Tour cards stay on top - Jira")
        #expect(model.history.visits.first?.transition == .inPage)
        #expect(model.history.entries.first { $0.url == "https://jira.example/board" }?.title == "Board - Jira")
    }

    @Test func onlyTheActiveTabIsMarkedActive() {
        let model = makeModel()
        let first = model.newTab()
        let second = model.newTab()
        #expect(second.isSidebarActive)
        #expect(!first.isSidebarActive)

        model.activate(first)
        #expect(first.isSidebarActive)
        #expect(!second.isSidebarActive)

        model.close(first)
        #expect(model.activeTab === second)
        #expect(second.isSidebarActive)
        #expect(model.tabs.filter(\.isSidebarActive).count == 1)
    }

    @Test func theStartPagePinsLikeAnyOtherPage() async {
        let model = makeModel()
        let tab = model.newTab()
        #expect(await settled(tab, at: SystemPages.start))

        model.pin(tab)
        #expect(tab.pinnedURL == SystemPages.start)
        #expect(tab.isShowingPin)
        #expect(!tab.isAwayFromPin)

        tab.urlString = "https://example.com/"
        #expect(tab.isAwayFromPin)
        #expect(!tab.isShowingPin)
    }

    @Test func draggingTheStartPageIntoThePinnedSectionPinsIt() async {
        let model = makeModel()
        let tab = model.newTab()
        #expect(await settled(tab, at: SystemPages.start))

        model.setPinned(true, for: [.tab(tab.id)])
        #expect(tab.pinnedURL == SystemPages.start)
        #expect(tab.pinnedTitle == SystemPages.startTitle)
    }
}
