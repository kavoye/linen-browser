// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct TabOrderingTests {
    private func makeModel() -> BrowserModel {
        BrowserModel(database: .temporary())
    }

    // MARK: - Cycling

    @Test func cyclingForwardWrapsPastTheLastTab() {
        let model = makeModel()
        let third = model.newTab()
        let second = model.newTab()
        let first = model.newTab()
        model.activate(third)

        model.cycleTab(forward: true)

        #expect(model.activeTab === first)
        _ = second
    }

    @Test func cyclingBackwardWrapsPastTheFirstTab() {
        let model = makeModel()
        let last = model.newTab()
        _ = model.newTab()
        let first = model.newTab()
        model.activate(first)

        model.cycleTab(forward: false)

        #expect(model.activeTab === last)
    }

    @Test func cyclingWalksTheListOneStepAtATime() {
        let model = makeModel()
        _ = model.newTab()
        let middle = model.newTab()
        let top = model.newTab()
        model.activate(top)

        model.cycleTab(forward: true)

        #expect(model.activeTab === middle)
    }

    @Test func cyclingASingleTabLeavesItWhereItIs() {
        let model = makeModel()
        let only = model.newTab()

        model.cycleTab(forward: true)
        model.cycleTab(forward: false)

        #expect(model.activeTab === only)
    }

    @Test func cyclingThereAndBackReturnsToWhereItStarted() {
        let model = makeModel()
        _ = model.newTab()
        _ = model.newTab()
        let start = model.newTab()
        model.activate(start)

        model.cycleTab(forward: true)
        model.cycleTab(forward: false)

        #expect(model.activeTab === start)
    }

    // MARK: - Jumping

    @Test func theLastTabShortcutGoesToTheBottomOfTheList() {
        let model = makeModel()
        let bottom = model.newTab()
        _ = model.newTab()
        _ = model.newTab()

        model.activateLastTab()

        #expect(model.activeTab === bottom)
        #expect(model.tabs.last === bottom)
    }

    @Test func theLastTabShortcutOnAnEmptyWindowDoesNothing() {
        let model = makeModel()
        model.activateLastTab()
        #expect(model.activeTab == nil)
    }

    @Test func aTabIsPickedByItsPositionFromTheTop() {
        let model = makeModel()
        _ = model.newTab()
        let middle = model.newTab()
        _ = model.newTab()

        model.activateTab(at: 1)

        #expect(model.activeTab === middle)
    }

    @Test func aPositionPastTheEndChangesNothing() {
        let model = makeModel()
        let only = model.newTab()

        model.activateTab(at: 9)
        #expect(model.activeTab === only)

        model.activateTab(at: -1)
        #expect(model.activeTab === only)
    }

    // MARK: - What can be reopened

    @Test func nothingClosedMeansNothingToReopen() {
        let model = makeModel()
        _ = model.newTab()
        #expect(!model.canReopenClosedTab)
    }

    @Test func closingATabMakesItReopenable() {
        let model = makeModel()
        _ = model.newTab()
        let doomed = model.newTab()

        model.close(doomed)

        #expect(model.canReopenClosedTab)
    }

    @Test func aPrivateTabIsNeverRecordedForReopening() {
        let model = makeModel()
        model.opensPrivately = true
        let secret = model.newTab(url: URL(string: "https://example.com/secret")!)

        model.close(secret)

        #expect(!model.canReopenClosedTab)
        #expect(model.closedTabs.isEmpty)
    }

    @Test func theReopenListRemembersTheLastTwentyClosings() {
        let model = makeModel()
        for index in 0..<25 {
            let tab = model.newTab()
            tab.title = "tab \(index)"
            model.close(tab)
        }

        #expect(model.closedTabs.count == 20)
        #expect(model.closedTabs.first?.title == "tab 5")
        #expect(model.closedTabs.last?.title == "tab 24")
    }

    @Test func reopeningTakesTheMostRecentlyClosedFirst() {
        let model = makeModel()
        let older = model.newTab()
        older.title = "older"
        let newer = model.newTab()
        newer.title = "newer"
        model.close(older)
        model.close(newer)

        model.reopenLastClosedTab()

        #expect(model.activeTab?.title == "newer")
        #expect(model.closedTabs.count == 1)
    }

    @Test func reopeningEmptiesTheEntryItUsed() {
        let model = makeModel()
        let doomed = model.newTab()
        model.close(doomed)

        model.reopenLastClosedTab()

        #expect(!model.canReopenClosedTab)
    }

    @Test func aTabWhoseFolderIsGoneComesBackToTheTopLevel() {
        let model = makeModel()
        let tab = model.newTab()
        let folder = model.createFolder(containing: [tab])
        model.close(tab)
        model.deleteFolder(folder)

        model.reopenLastClosedTab()

        #expect(model.tabs.count == 1)
        let restored = model.activeTab
        #expect(restored != nil)
        #expect(restored.flatMap { model.folder(containing: $0) } == nil)
    }

    // MARK: - Folders read at two depths

    private func nested() -> NestedFolders {
        let model = makeModel()
        let inner = model.newTab()
        let outer = model.newTab()
        let child = model.createFolder(named: "Child", containing: [inner])
        let parent = model.createFolder(named: "Parent", containing: [outer])
        model.move([.folder(child.id)], into: parent)
        return NestedFolders(model: model, parent: parent, child: child, outer: outer, inner: inner)
    }

    @Test func aFoldersOwnRowsStopAtItsSubfolders() {
        let nest = nested()

        let direct = nest.model.tabs(in: nest.parent)

        #expect(direct.contains { $0 === nest.outer })
        #expect(!direct.contains { $0 === nest.inner })
    }

    @Test func everythingUnderAFolderReachesIntoItsSubfolders() {
        let nest = nested()

        let all = nest.model.allTabs(in: nest.parent)

        #expect(all.contains { $0 === nest.outer })
        #expect(all.contains { $0 === nest.inner })
    }

    @Test func countingASelectionReachesTheSameDepth() {
        let nest = nested()
        #expect(nest.model.tabCount(in: [.folder(nest.parent.id)]) == 2)
    }

    @Test func countingALooseTabCountsOne() {
        let model = makeModel()
        let tab = model.newTab()
        #expect(model.tabCount(in: [.tab(tab.id)]) == 1)
    }

    @Test func aTabInASubfolderNamesThatSubfolderAsItsParent() {
        let nest = nested()

        #expect(nest.model.folder(containing: nest.inner) === nest.child)
        #expect(nest.model.folder(containing: nest.child) === nest.parent)
        #expect(nest.model.folder(containing: nest.parent) == nil)
    }

    @Test func aLooseTabHasNoFolder() {
        let model = makeModel()
        let tab = model.newTab()
        #expect(model.folder(containing: tab) == nil)
        #expect(model.ungroupedTabs.contains { $0 === tab })
    }

    @Test func aFolderedTabIsNoLongerLoose() {
        let model = makeModel()
        let tab = model.newTab()
        model.createFolder(containing: [tab])
        #expect(!model.ungroupedTabs.contains { $0 === tab })
    }

    // MARK: - Folder colour

    @Test func aFolderKeepsTheColorItWasGiven() {
        let model = makeModel()
        let folder = model.createFolder()

        model.setFolderColor(.teal, for: folder)

        #expect(folder.color == .teal)
    }

    @Test func settingTheColorItAlreadyHasChangesNothing() {
        let model = makeModel()
        let folder = model.createFolder()
        model.setFolderColor(.orange, for: folder)

        model.setFolderColor(.orange, for: folder)

        #expect(folder.color == .orange)
    }

    // MARK: - Renaming

    @Test func aFolderTakesTheNameItWasGivenWithoutItsSurroundingSpace() {
        let model = makeModel()
        let folder = model.createFolder()

        model.renameFolder(folder, to: "  Reading  ")

        #expect(folder.name == "Reading")
    }

    @Test func aNameOfNothingButSpaceIsRefused() {
        let model = makeModel()
        let folder = model.createFolder(named: "Reading")

        model.renameFolder(folder, to: "   \n ")

        #expect(folder.name == "Reading")
    }
}

@MainActor
private struct NestedFolders {
    let model: BrowserModel
    let parent: TabFolder
    let child: TabFolder
    let outer: BrowserTab
    let inner: BrowserTab
}
