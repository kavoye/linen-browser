// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// The sidebar's arrangement. Folders and tabs share one order at every level,
/// a row can be dragged anywhere another row can go, a folder can never end up
/// inside itself, and the whole thing has to survive a mutation that forgets to
/// mention it.
struct SidebarTreeTests {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID()
    private let folder1 = UUID(), folder2 = UUID(), folder3 = UUID()

    private func always(_ id: UUID) -> Bool {
        true
    }

    // MARK: - Reconciliation

    @Test func keepsTheOrderTheUserDraggedRowsInto() {
        let stored = SidebarTree(root: [.tab(c), .tab(a), .tab(b)])
        let tree = SidebarTree.reconcile(stored: stored, folders: [], tabs: [a, b, c])
        #expect(tree.root == [.tab(c), .tab(a), .tab(b)])
    }

    /// The self-healing half: a tab that was never added to the stored tree
    /// still has to appear. Dropping it would be a row that exists in the model
    /// and nowhere on screen.
    @Test func placesRowsTheStoredTreeNeverHeardOf() {
        let tree = SidebarTree.reconcile(
            stored: SidebarTree(root: [.tab(c)]),
            folders: [],
            tabs: [a, b, c]
        )
        #expect(tree.root == [.tab(c), .tab(a), .tab(b)])
    }

    @Test func forgetsRowsThatNoLongerExist() {
        let stored = SidebarTree(root: [.tab(b), .tab(a), .folder(folder1)])
        let tree = SidebarTree.reconcile(stored: stored, folders: [], tabs: [a])
        #expect(tree.root == [.tab(a)])
    }

    /// A stored tree with the same row twice would otherwise draw it twice and
    /// push a real row off the end of the list.
    @Test func neverPlacesTheSameRowTwice() {
        let stored = SidebarTree(
            root: [.tab(a), .folder(folder1), .tab(a)],
            children: [folder1: [.tab(a), .tab(b)]]
        )
        let tree = SidebarTree.reconcile(stored: stored, folders: [folder1], tabs: [a, b])
        #expect(tree.walk() == [.tab(a), .folder(folder1), .tab(b)])
    }

    @Test func startsFromNothingWithoutLosingAnything() {
        let tree = SidebarTree.reconcile(stored: SidebarTree(), folders: [folder1], tabs: [a, b])
        // Folders first, then the loose tabs: where they sit before anyone has
        // dragged anything.
        #expect(tree.root == [.folder(folder1), .tab(a), .tab(b)])
    }

    @Test func keepsNesting() {
        let stored = SidebarTree(
            root: [.folder(folder1)],
            children: [folder1: [.folder(folder2), .tab(a)], folder2: [.tab(b)]]
        )
        let tree = SidebarTree.reconcile(stored: stored, folders: [folder1, folder2], tabs: [a, b])
        #expect(tree.walk() == [.folder(folder1), .folder(folder2), .tab(b), .tab(a)])
        #expect(tree.depth(of: .tab(b)) == 2)
    }

    /// A session file naming a folder inside itself would send the walk round
    /// forever, and every row under it would be unreachable.
    @Test func breaksACycleByPuttingTheFolderBackAtTheTop() {
        let stored = SidebarTree(
            root: [.tab(a)],
            children: [folder1: [.folder(folder2)], folder2: [.folder(folder1), .tab(b)]]
        )
        let tree = SidebarTree.reconcile(stored: stored, folders: [folder1, folder2], tabs: [a, b])
        let walk = tree.walk()
        #expect(Set(walk) == [.tab(a), .tab(b), .folder(folder1), .folder(folder2)])
        #expect(walk.count == 4)
        #expect(tree.parent(of: .folder(folder1)) == nil)
    }

    @Test func dropsWhatAVanishedFolderHeldBackToTheTop() {
        let stored = SidebarTree(root: [.folder(folder1)], children: [folder1: [.tab(a), .tab(b)]])
        let tree = SidebarTree.reconcile(stored: stored, folders: [], tabs: [a, b])
        #expect(tree.root == [.tab(a), .tab(b)])
        #expect(tree.children.isEmpty)
    }

    // MARK: - Moving

    private var nested: SidebarTree {
        SidebarTree(
            root: [.tab(a), .folder(folder1), .tab(d)],
            children: [folder1: [.tab(b), .folder(folder2)], folder2: [.tab(c)]]
        )
    }

    @Test func movesARowUp() {
        let tree = nested.moving([.tab(d)], into: nil, before: .tab(a))
        #expect(tree?.root == [.tab(d), .tab(a), .folder(folder1)])
    }

    /// The off-by-one every list reorder has: dragging downwards has to land
    /// *before* the target, which means the target's index is only correct once
    /// the dragged row has been taken out.
    @Test func movesARowDownWithoutOvershooting() {
        let flat = SidebarTree(root: [.tab(a), .tab(b), .tab(c), .tab(d)])
        #expect(
            flat.moving([.tab(a)], into: nil, before: .tab(c))?.root
                == [.tab(b), .tab(a), .tab(c), .tab(d)]
        )
    }

    @Test func aNilTargetMeansTheEndOfThatLevel() {
        #expect(nested.moving([.tab(a)], into: folder1, before: nil)?.rows(in: folder1)
            == [.tab(b), .folder(folder2), .tab(a)])
    }

    @Test func movingARowOntoItselfDoesNothing() {
        #expect(nested.moving([.tab(a)], into: nil, before: .tab(a)) == nil)
    }

    @Test func aMoveThatChangesNothingIsNotAMove() {
        #expect(nested.moving([.tab(b)], into: folder1, before: .folder(folder2)) == nil)
    }

    @Test func aFolderTakesWhatItHoldsWithIt() {
        let tree = nested.moving([.folder(folder1)], into: nil, before: .tab(a))
        #expect(tree?.root == [.folder(folder1), .tab(a), .tab(d)])
        #expect(tree?.rows(in: folder1) == [.tab(b), .folder(folder2)])
        #expect(tree?.rows(in: folder2) == [.tab(c)])
    }

    @Test func aFolderCanBeDroppedIntoAnotherFolder() {
        let tree = SidebarTree(
            root: [.folder(folder1), .folder(folder2)],
            children: [folder1: [.tab(a)], folder2: [.tab(b)]]
        )
        let moved = tree.moving([.folder(folder2)], into: folder1, before: .tab(a))
        #expect(moved?.root == [.folder(folder1)])
        #expect(moved?.rows(in: folder1) == [.folder(folder2), .tab(a)])
        #expect(moved?.depth(of: .tab(b)) == 2)
    }

    /// The one move that must be refused: everything under the folder would be
    /// reachable only from inside itself, which is to say gone.
    @Test func aFolderCannotBeDroppedIntoItself() {
        #expect(nested.moving([.folder(folder1)], into: folder1, before: nil) == nil)
        #expect(nested.moving([.folder(folder1)], into: folder2, before: nil) == nil)
        #expect(nested.canHold(folder2, [.folder(folder1)]) == false)
        #expect(nested.canHold(folder2, [.tab(a)]))
    }

    @Test func manyRowsMoveTogetherAndKeepTheirOrder() {
        let flat = SidebarTree(root: [.tab(a), .tab(b), .tab(c), .tab(d)])
        #expect(
            flat.moving([.tab(a), .tab(c)], into: nil, before: nil)?.root
                == [.tab(b), .tab(d), .tab(a), .tab(c)]
        )
    }

    /// Repeated moves must not lose or duplicate a row, whatever order they
    /// arrive in - this runs on every pointer move during a drag.
    @Test func repeatedMovesConserveEveryRow() {
        var tree = nested
        let original = Set(tree.walk())
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<400 {
            let rows = tree.walk()
            let item = rows.randomElement(using: &generator)!
            let target = Bool.random(using: &generator) ? rows.randomElement(using: &generator) : nil
            let parent: UUID? = Bool.random(using: &generator)
                ? [folder1, folder2].randomElement(using: &generator)
                : nil
            if let next = tree.moving([item], into: parent, before: target) {
                tree = next
            }
            let walk = tree.walk()
            #expect(Set(walk) == original)
            #expect(walk.count == original.count)
        }
    }

    // MARK: - Duplicating

    @Test func aDuplicateLandsDirectlyUnderItsOriginal() {
        let tree = SidebarTree(root: [.tab(a), .tab(b), .tab(c)])
        #expect(tree.inserting(.tab(d), after: .tab(a)).root == [.tab(a), .tab(d), .tab(b), .tab(c)])
    }

    /// The copy is a real tab before it is placed, so the reconciled tree
    /// handed in already mentions it - once, at the end. Left there, that entry
    /// is the one the sidebar would keep.
    @Test func aDuplicateAlreadyInTheTreeMovesRatherThanRepeats() {
        let tree = SidebarTree(root: [.tab(a), .tab(b), .tab(d)])
        let placed = tree.inserting(.tab(d), after: .tab(a)).root
        #expect(placed == [.tab(a), .tab(d), .tab(b)])
        #expect(placed.count == Set(placed).count)
    }

    @Test func aDuplicateOfATabInAFolderStaysInThatFolder() {
        let placed = nested.inserting(.tab(d), after: .tab(b))
        #expect(placed.rows(in: folder1) == [.tab(b), .tab(d), .folder(folder2)])
        #expect(placed.root == [.tab(a), .folder(folder1)])
    }

    // MARK: - Deleting a folder

    @Test func whatAFolderHeldTakesItsPlace() {
        let tree = nested.dissolving(folder1)
        #expect(tree.root == [.tab(a), .tab(b), .folder(folder2), .tab(d)])
        #expect(tree.rows(in: folder2) == [.tab(c)])
    }

    // MARK: - Flattening

    @Test func readsFoldersInPlaceAndLooseTabsAsThemselves() {
        #expect(nested.flattenedTabs(known: [a, b, c, d]) == [a, b, c, d])
    }

    /// Cycling with ⌃Tab walks this list, so a tab appearing twice would make
    /// the cycle stutter and a missing one would make it unreachable.
    @Test func ignoresTabsThatNoLongerExist() {
        #expect(nested.flattenedTabs(known: [a, c]) == [a, c])
    }

    // MARK: - What is on screen

    @Test func aShutFolderContributesOnlyItself() {
        let shut = nested.visibleRows { $0 != self.folder1 }
        #expect(shut == [.tab(a), .folder(folder1), .tab(d)])
        #expect(nested.visibleRows(isExpanded: always).count == 6)
    }

    @Test func aRangeReachesOverWhateverIsOnScreen() {
        let range = nested.range(from: .tab(a), to: .tab(c), isExpanded: always)
        #expect(range == [.tab(a), .folder(folder1), .tab(b), .folder(folder2), .tab(c)])
    }

    @Test func aRangeReadsTheSameWayUpwards() {
        let down = nested.range(from: .tab(a), to: .tab(d), isExpanded: always)
        let up = nested.range(from: .tab(d), to: .tab(a), isExpanded: always)
        #expect(down == up)
    }

    // MARK: - Selections

    /// Dragging a folder and a tab inside it must move the folder alone -
    /// moving both would take that tab out of the folder travelling with it.
    @Test func aSelectionDropsWhateverASelectedFolderAlreadyHolds() {
        #expect(nested.normalized([.folder(folder1), .tab(b), .tab(c)]) == [.folder(folder1)])
        #expect(nested.normalized([.tab(a), .tab(c)]) == [.tab(a), .tab(c)])
    }

    /// A selection is a set and has no order of its own, so it takes the
    /// sidebar's - the rows must land in the order they were picked up in.
    @Test func aNormalizedSelectionIsInReadingOrder() {
        let selection: Set<SidebarItem> = [.tab(d), .tab(a)]
        #expect(nested.normalized(selection) == [.tab(a), .tab(d)])
    }

    /// A list, though, is somebody saying what order they want - the import
    /// hands over bookmarks in file order, and they must stay in it.
    @Test func aNormalizedListKeepsTheOrderItWasGiven() {
        #expect(nested.normalized([.tab(d), .tab(a)]) == [.tab(d), .tab(a)])
    }

    @Test func aSelectedFolderStandsForEverythingUnderIt() {
        #expect(
            nested.expanded([.folder(folder1)])
                == [.folder(folder1), .tab(b), .folder(folder2), .tab(c)]
        )
    }
}

/// What the edge is allowed to do while it is being dragged. The two stages
/// have different floors, and the gap between them is where the titled layout
/// used to be drawn in a column too narrow to hold it.
@MainActor
struct SidebarDragTests {
    private func layout() -> SidebarLayout {
        let defaults = UserDefaults(suiteName: "linen.tests.sidebar.\(UUID().uuidString)")!
        return SidebarLayout(defaults: defaults)
    }

    private let container: CGFloat = 1600

    @Test func theFullColumnStopsAtItsMinimumInsteadOfSqueezing() {
        let sidebar = layout()
        // In past the point where the titled layout stops fitting, but not as
        // far as the compact threshold.
        sidebar.dragChanged(
            translation: SidebarMetrics.iconsSnap + 10 - SidebarMetrics.defaultWidth,
            container: container
        )
        #expect(sidebar.style == .full)
        #expect(sidebar.openWidth(in: container) == SidebarMetrics.minWidth)
    }

    @Test func theCompactColumnTracksThePointerBelowTheThreshold() {
        let sidebar = layout()
        let target = SidebarMetrics.iconsSnap - 20
        sidebar.dragChanged(translation: target - SidebarMetrics.defaultWidth, container: container)
        #expect(sidebar.style == .icons)
        // Deliberately not the compact width: the column follows the pointer
        // through the gesture and snaps only once, on release, so WebKit is
        // handed one resize instead of one per frame.
        #expect(sidebar.openWidth(in: container) == target)

        sidebar.dragEnded(translation: target - SidebarMetrics.defaultWidth, container: container)
        #expect(sidebar.openWidth(in: container) == SidebarMetrics.iconsWidth)
    }

    @Test func theFloorNeverPushesPastTheWindowsOwnCeiling() {
        let sidebar = layout()
        // A window too small for the sidebar's usual room: the fraction of the
        // window wins, and the floor must not drag the column back over it.
        let narrow: CGFloat = 300
        sidebar.dragChanged(translation: -SidebarMetrics.defaultWidth, container: narrow)
        let ceiling = max(SidebarMetrics.minWidth, narrow * SidebarMetrics.maxWindowFraction)
        #expect(sidebar.openWidth(in: narrow) <= ceiling)
    }
}
