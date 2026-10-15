// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct SpaceTests {
    private let home = UUID()
    private let recipes = UUID()

    private func makeModel(database: AppDatabase = .temporary()) -> BrowserModel {
        let model = BrowserModel(database: database)
        model.adoptSpaces([home, recipes])
        return model
    }

    private func listedTabs(_ model: BrowserModel) -> [UUID] {
        model.sidebarTree.flattenedTabs(known: Set(model.tabsByID.keys))
    }

    // MARK: - The list

    @Test func newTabsJoinTheCurrentSpace() {
        let model = makeModel()
        let tab = model.newTab()

        #expect(tab.spaceID == home)
    }

    @Test func theSidebarListsOnlyTheCurrentSpace() throws {
        let model = makeModel()
        let homeTab = model.newTab()
        model.switchSpace(to: recipes)
        let recipeTab = try #require(model.activeTab)

        #expect(listedTabs(model) == [recipeTab.id])
        model.switchSpace(to: home)
        #expect(listedTabs(model) == [homeTab.id])
    }

    @Test func switchingToAnEmptySpaceOpensATabThere() {
        let model = makeModel()
        _ = model.newTab()

        model.switchSpace(to: recipes)

        #expect(model.currentSpaceID == recipes)
        #expect(model.activeTab?.spaceID == recipes)
    }

    @Test func switchingBackReturnsToTheLastActiveTab() {
        let model = makeModel()
        let first = model.newTab()
        _ = model.newTab()
        model.activate(first)
        model.switchSpace(to: recipes)

        model.switchSpace(to: home)

        #expect(model.activeTab === first)
    }

    @Test func activatingATabInAnotherSpaceReportsIt() {
        let model = makeModel()
        let homeTab = model.newTab()
        model.switchSpace(to: recipes)
        var reported: BrowserTab?
        model.onActiveTabLeftSpace = { reported = $0 }

        model.activate(homeTab)

        #expect(reported === homeTab)
        #expect(model.currentSpaceID == recipes)
    }

    // MARK: - Navigation stays in the space

    @Test func closingTheActiveTabPicksANeighborInTheSameSpace() throws {
        let model = makeModel()
        let homeTab = model.newTab()
        model.switchSpace(to: recipes)
        let recipeTab = try #require(model.activeTab)
        let second = model.newTab()
        model.activate(recipeTab)
        try #require(model.tabs.map(\.id) == [second.id, recipeTab.id, homeTab.id])

        model.close(recipeTab)

        #expect(model.activeTab === second)
    }

    @Test func numberedTabsCountOnlyTheCurrentSpace() throws {
        let model = makeModel()
        let homeTab = model.newTab()
        model.switchSpace(to: recipes)
        let recipeTab = try #require(model.activeTab)
        let second = model.newTab()
        try #require(model.tabs.map(\.id) == [second.id, recipeTab.id, homeTab.id])

        model.activateTab(at: 2)
        #expect(model.activeTab === second)

        model.activateTab(at: 1)
        #expect(model.activeTab === recipeTab)
    }

    @Test func closeOthersLeavesOtherSpacesAlone() throws {
        let model = makeModel()
        let homeTab = model.newTab()
        model.switchSpace(to: recipes)
        let kept = try #require(model.activeTab)
        _ = model.newTab()

        model.closeOthers(kept)

        #expect(Set(model.tabs.map(\.id)) == [homeTab.id, kept.id])
    }

    @Test func eachSpaceKeepsItsOwnRootItems() {
        let model = makeModel()
        let homeTab = model.newTab()
        model.switchSpace(to: recipes)
        let recipeTab = model.newTab()

        #expect(model.rootItems(inSpace: home) == [.tab(homeTab.id)])
        #expect(model.rootItems(inSpace: recipes).contains(.tab(recipeTab.id)))
        #expect(!model.rootItems(inSpace: recipes).contains(.tab(homeTab.id)))
    }

    @Test func theLastActiveTabOfASpaceIsTheOneUsedLast() {
        let model = makeModel()
        let first = model.newTab()
        let second = model.newTab()
        model.activate(first)
        model.switchSpace(to: recipes)

        #expect(model.lastActiveTab(inSpace: home) === first)
        #expect(model.lastActiveTab(inSpace: home) !== second)
    }

    // MARK: - Moving between spaces

    @Test func movingATabTakesItToTheOtherSpace() {
        let model = makeModel()
        let stays = model.newTab()
        let moves = model.newTab()

        model.move([.tab(moves.id)], toSpace: recipes)

        #expect(moves.spaceID == recipes)
        #expect(listedTabs(model) == [stays.id])
        #expect(model.activeTab === stays)
    }

    @Test func aFolderCarriesItsTabsToTheOtherSpace() {
        let model = makeModel()
        let tab = model.newTab()
        let folder = model.createFolder(containing: [tab])

        model.move([.folder(folder.id)], toSpace: recipes)

        #expect(folder.spaceID == recipes)
        #expect(tab.spaceID == recipes)
    }

    @Test func aTabFromAnUnknownSpaceJoinsTheCurrentOne() {
        let model = makeModel()
        let tab = model.newTab()
        tab.spaceID = UUID()

        model.sidebarDidChange()

        #expect(tab.spaceID == home)
    }

    @Test func closingASpaceClosesOnlyItsTabs() {
        let model = makeModel()
        let homeTab = model.newTab()
        model.switchSpace(to: recipes)
        model.switchSpace(to: home)

        model.closeSpace(recipes)

        #expect(model.tabs.map(\.id) == [homeTab.id])
    }

    // MARK: - Saving

    @Test func aRestoredSessionKeepsEachTabInItsSpace() throws {
        let database = AppDatabase.temporary()
        let first = makeModel(database: database)
        let homeTab = first.newTab()
        first.switchSpace(to: recipes)
        let recipeTab = try #require(first.activeTab)
        first.saveBlocking()

        let reopened = makeModel(database: database)
        reopened.restoreSession()

        #expect(reopened.tab(id: homeTab.id)?.spaceID == home)
        #expect(reopened.tab(id: recipeTab.id)?.spaceID == recipes)
        #expect(reopened.currentSpaceID == recipes)
    }

    @Test func aLazyRestoreLoadsNoPagesAndStaysClosed() throws {
        let database = AppDatabase.temporary()
        let first = makeModel(database: database)
        let tab = first.newTab(url: URL(string: "https://example.com")!)
        first.markSessionClosed()

        let parked = makeModel(database: database)
        parked.restoreSession(lazily: true)
        parked.saveBlocking()

        let restored = try #require(parked.tab(id: tab.id))
        #expect(!restored.isMaterialised)
        #expect(parked.activeTabID == nil)
        #expect(parked.recentlyActive == [tab.id])
        let open = BrowserModel.savedWindows(in: database).map(\.id)
        #expect(!open.contains(parked.windowID))
    }

    @Test func reopeningAParkedModelShowsItsLastTab() throws {
        let database = AppDatabase.temporary()
        let first = makeModel(database: database)
        let tab = first.newTab(url: URL(string: "https://example.com")!)
        first.markSessionClosed()

        let parked = makeModel(database: database)
        parked.restoreSession(lazily: true)
        parked.reopenSession()

        #expect(parked.activeTabID == tab.id)
        #expect(BrowserModel.savedWindows(in: database).map(\.id).contains(parked.windowID))
    }
}

@MainActor
@Suite
struct SpaceStoreTests {
    private func makeStore() -> (SpaceStore, URL) {
        let file = TestFiles.directory.appendingPathComponent("spaces-\(UUID().uuidString).json")
        return (SpaceStore(file: file), file)
    }

    @Test func everyProfileGetsASpace() {
        let (store, _) = makeStore()
        let work = Profile(id: UUID(), name: "Work", symbol: "briefcase", color: .blue)

        store.reconcile(with: [.original(), work])

        #expect(store.spaces.map(\.profileID) == [Profile.originalID, work.id])
        #expect(store.spaces.last?.name == "Work")
    }

    @Test func spacesOfARemovedProfileGoAway() {
        let (store, _) = makeStore()
        let work = Profile(id: UUID(), name: "Work", symbol: "briefcase", color: .blue)
        store.reconcile(with: [.original(), work])

        store.reconcile(with: [.original()])

        #expect(store.spaces.map(\.profileID) == [Profile.originalID])
    }

    @Test func theLastSpaceOfTheOriginalProfileStays() throws {
        let (store, _) = makeStore()
        let work = Profile(id: UUID(), name: "Work", symbol: "briefcase", color: .blue)
        store.reconcile(with: [.original(), work])
        let original = try #require(store.spaces.first)

        store.remove(original)

        #expect(store.spaces.contains(original))
    }

    @Test func spacesSurviveAReload() {
        let (store, file) = makeStore()
        store.reconcile(with: [.original()])
        let added = store.add(name: "Recipes", symbol: "fork.knife", color: .orange, profileID: Profile.originalID)

        #expect(SpaceStore(file: file).spaces.last == added)
    }
}
