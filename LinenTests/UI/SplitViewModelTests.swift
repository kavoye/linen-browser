// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// Splits as the browser sees them, rather than as arithmetic over ids - see
/// `TabSplitTests` for that half. What matters here: the pair sits together in
/// the sidebar, a visible pane is never swept, and every way a tab can leave
/// takes its split with it.
@MainActor
struct SplitViewModelTests {
    private func makeModel() -> BrowserModel {
        BrowserModel(
            database: .temporary(),
            sitePermissions: SitePermissions(
                storageURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("SplitPermissions-\(UUID().uuidString).json")
            )
        )
    }

    // MARK: - Display

    /// The rule the whole feature hangs off: a split is drawn only while the
    /// active tab is one of its two.
    @Test func showsTheSplitOnlyWhileOneOfItsTabsIsActive() {
        let model = makeModel()
        let other = model.newTab(url: URL(string: "https://example.com/c"))
        let left = model.newTab(url: URL(string: "https://example.com/a"))
        let right = model.newTab(url: URL(string: "https://example.com/b"))
        model.split(left, with: right, axis: .sideBySide)

        model.activate(right)
        #expect(model.splitPanes?.map(\.id) == [left.id, right.id])

        model.activate(other)
        #expect(model.activeSplit == nil)
        #expect(model.splitPanes == nil)

        // And coming back shows the pair again - it was never dissolved.
        model.activate(left)
        #expect(model.splitPanes?.map(\.id) == [left.id, right.id])
    }

    // MARK: - The sidebar row

    /// The pair draws as one row at the leading tab's place, so the trailing
    /// tab has to be there too.
    @Test func gathersTheTrailingTabNextToTheLeadingOne() {
        let model = makeModel()
        let left = model.newTab(url: URL(string: "https://example.com/a"))
        _ = model.newTab(url: URL(string: "https://example.com/spacer"))
        let right = model.newTab(url: URL(string: "https://example.com/b"))

        model.split(left, with: right, axis: .sideBySide)

        let rows = model.sidebarTree.walk()
        let at = rows.firstIndex(of: .tab(left.id))
        #expect(at != nil)
        #expect(rows[(at ?? 0) + 1] == .tab(right.id))
    }

    @Test func carriesTheTrailingTabIntoTheLeadingTabsFolder() {
        let model = makeModel()
        let left = model.newTab(url: URL(string: "https://example.com/a"))
        let right = model.newTab(url: URL(string: "https://example.com/b"))
        let folder = model.createFolder(named: "Work", containing: [left])

        model.split(left, with: right, axis: .stacked)

        #expect(model.folder(containing: right) === folder)
        #expect(model.tabs(in: folder).map(\.id) == [left.id, right.id])
    }

    @Test func swappingPanesSwapsTheRowToo() {
        let model = makeModel()
        let left = model.newTab(url: URL(string: "https://example.com/a"))
        let right = model.newTab(url: URL(string: "https://example.com/b"))
        model.split(left, with: right, axis: .sideBySide)

        model.swapSplitRow(containing: left)

        #expect(model.activeSplit?.leader == right.id)
        let rows = model.sidebarTree.walk()
        #expect(rows.firstIndex(of: .tab(right.id))! < rows.firstIndex(of: .tab(left.id))!)
    }

    @Test func aReplacedPaneLeavesItsTabWhereItAlreadyWas() {
        let model = makeModel()
        let left = model.newTab(url: URL(string: "https://example.com/a"))
        let right = model.newTab(url: URL(string: "https://example.com/b"))
        let third = model.newTab(url: URL(string: "https://example.com/c"))
        model.split(left, with: right, axis: .sideBySide)

        model.replaceSplitPane(right, with: third)

        #expect(model.splits.others(of: left.id) == [third.id])
        #expect(model.tabs.contains { $0 === right })
        let rows = model.sidebarTree.walk()
        #expect(rows[rows.firstIndex(of: .tab(left.id))! + 1] == .tab(third.id))
    }

    // MARK: - A link opened beside its page

    /// Shift-clicking a link puts it beside the page it was on, and focus goes
    /// with it - the click asked for that page.
    @Test func aLinkOpenedBesideItsPageMakesASplit() throws {
        let model = makeModel()
        let reading = model.newTab(url: URL(string: "https://example.com/article"))
        model.activate(reading)

        let open = try #require(reading.onOpenInSplit)
        open(URL(string: "https://example.com/reference")!)

        let split = try #require(model.activeSplit)
        #expect(split.count == 2)
        #expect(split.leader == reading.id)
        #expect(model.activeTabID != reading.id)
    }

    /// And it joins a grid that already exists rather than starting a second.
    @Test func aLinkOpenedBesideAGridJoinsIt() throws {
        let model = makeModel()
        let left = model.newTab(url: URL(string: "https://example.com/a"))
        let right = model.newTab(url: URL(string: "https://example.com/b"))
        model.split(left, with: right, axis: .sideBySide)
        model.activate(right)

        let open = try #require(right.onOpenInSplit)
        open(URL(string: "https://example.com/c")!)

        #expect(model.activeSplit?.count == 3)
        #expect(model.splits.splits.count == 1)
    }

    /// A grid at the page ceiling has nowhere to put it, and the page the link
    /// was on must not be the one that gives way.
    @Test func aLinkOpenedBesideAFullGridOpensAnOrdinaryTab() throws {
        let model = makeModel()
        let a = model.newTab(url: URL(string: "https://example.com/a"))
        let b = model.newTab(url: URL(string: "https://example.com/b"))
        let c = model.newTab(url: URL(string: "https://example.com/c"))
        let d = model.newTab(url: URL(string: "https://example.com/d"))
        model.split(a, with: b, axis: .sideBySide)
        model.insertIntoSplit(c, beside: b, edge: .right)
        model.insertIntoSplit(d, beside: c, edge: .right)
        model.activate(b)

        let open = try #require(b.onOpenInSplit)
        open(URL(string: "https://example.com/e")!)

        #expect(model.splits.contains(b.id))
        #expect(model.splits.split(containing: a.id)?.count == 4)
        #expect(model.activeSplit == nil)
    }

    // MARK: - Rearranging

    /// A divider is dragged at pointer rate, so the model takes where it landed
    /// rather than how far it came - and the shortest a pane may be is a length
    /// in points, which only the view can turn into a share.
    @Test func draggingADividerMovesOnlyItsOwnPair() throws {
        let model = makeModel()
        let a = model.newTab(url: URL(string: "https://example.com/a"))
        let b = model.newTab(url: URL(string: "https://example.com/b"))
        let c = model.newTab(url: URL(string: "https://example.com/c"))
        model.split(a, with: b, axis: .sideBySide)
        model.insertIntoSplit(c, beside: b, edge: .right)

        let grid = try #require(model.activeSplit)
        let layout = SplitLayout(grid: grid, size: CGSize(width: 1200, height: 800), gutter: 6)
        let seam = try #require(layout.seams.first)
        model.setSplitSeam(seam, containing: a, leading: 0.9, minimum: 0.25)

        let shares = try #require(model.activeSplit?.root.children.map(\.share))
        // Clamped by the minimum, and the third pane untouched by either.
        #expect(shares[0].isApproximately(0.5625) == true)
        #expect(shares[2].isApproximately(0.25) == true)
    }

    // MARK: - A page in the air

    /// Loom places the complete split canvas below its glass beam. Carrying a
    /// pane can change the split geometry, but it must never reintroduce a
    /// toolbar inset inside the remaining web page.
    @Test func carryingAPaneKeepsTheOtherOneBelowTheBeam() {
        let model = makeModel()
        let top = model.newTab(url: URL(string: "https://a.example/"))
        let bottom = model.newTab(url: URL(string: "https://b.example/"))
        model.split(top, with: bottom, axis: .stacked)
        model.activate(bottom)
        #expect(!bottom.isUnderTopBar)

        model.paneInAir = top.id
        #expect(!bottom.isUnderTopBar)
    }

    /// Putting the page down again restores every one of those answers. A
    /// drag that ends without moving anything has to leave the split exactly
    /// as it found it - see the grip in `SplitSurface`, which stays in the
    /// view tree while it is carried precisely so that this runs.
    @Test func puttingACarriedPaneDownRestoresTheSplit() {
        let model = makeModel()
        let top = model.newTab(url: URL(string: "https://a.example/"))
        let bottom = model.newTab(url: URL(string: "https://b.example/"))
        model.split(top, with: bottom, axis: .stacked)
        model.activate(bottom)

        model.paneInAir = top.id
        model.paneInAir = nil

        #expect(model.activeSplit?.leader == top.id)
        #expect(model.splitPanes?.map(\.id) == [top.id, bottom.id])
        #expect(!top.isUnderTopBar)
        #expect(!bottom.isUnderTopBar)
    }

    // MARK: - Memory pressure

    /// The second pane is neither the active tab nor in the recently-active
    /// list, so nothing else would have spared a page the user is looking at.
    @Test func neverDiscardsTheOtherPane() {
        let model = makeModel()
        let left = model.newTab(url: URL(string: "https://example.com/a"))
        let right = model.newTab(url: URL(string: "https://example.com/b"))
        model.split(left, with: right, axis: .sideBySide)
        model.activate(right)

        model.discardBackgroundTabs()

        #expect(!left.isDeferred)
        #expect(model.protectionReason(for: left) == .visibleInSplit)
    }

    /// Only while it is on screen: a split the user has navigated away from
    /// protects nothing.
    @Test func discardsAPairedTabOnceTheSplitIsOffScreen() {
        let model = makeModel()
        let left = model.newTab(url: URL(string: "https://example.com/a"))
        let right = model.newTab(url: URL(string: "https://example.com/b"))
        model.split(left, with: right, axis: .sideBySide)
        let elsewhere = model.newTab(url: URL(string: "https://example.com/c"))
        model.activate(elsewhere)

        #expect(model.protectionReason(for: left) == nil)
        model.discardBackgroundTabs()
        #expect(left.isDeferred)
    }

    // MARK: - Leaving

    @Test func closingOnePaneHandsTheWindowToTheOther() {
        let model = makeModel()
        _ = model.newTab(url: URL(string: "https://example.com/elsewhere"))
        let left = model.newTab(url: URL(string: "https://example.com/a"))
        let right = model.newTab(url: URL(string: "https://example.com/b"))
        model.split(left, with: right, axis: .sideBySide)
        model.activate(right)

        model.close(right)

        #expect(model.activeTabID == left.id)
        #expect(model.activeSplit == nil)
        #expect(model.splits.isEmpty)
    }

    /// The surviving half has been a full-width page for however long by the
    /// time ⇧⌘T is pressed, and re-splitting under the user is worse than not.
    @Test func reopeningAClosedPaneDoesNotRestoreTheSplit() {
        let model = makeModel()
        let left = model.newTab(url: URL(string: "https://example.com/a"))
        let right = model.newTab(url: URL(string: "https://example.com/b"))
        model.split(left, with: right, axis: .sideBySide)

        model.close(right)
        model.reopenLastClosedTab()

        #expect(model.splits.isEmpty)
    }

    @Test func switchingProfilesTakesEverySplitWithIt() {
        let model = makeModel()
        let left = model.newTab(url: URL(string: "https://example.com/a"))
        let right = model.newTab(url: URL(string: "https://example.com/b"))
        model.split(left, with: right, axis: .stacked)

        model.closeAllTabs()

        #expect(model.splits.isEmpty)
    }
}
