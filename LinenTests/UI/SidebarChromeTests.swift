// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import CoreGraphics
import Foundation
import Testing
import WebKit

@testable import Linen

/// A sleeping tab says so on its favicon - dimmed, moon in the corner -
/// rather than with a second glyph beside the title.
@MainActor
struct SidebarSleepIndicatorTests {
    @Test func onlyAnUnloadedTabWearsTheMoon() {
        #expect(TabIcon.isAsleep(.unloaded))
        #expect(!TabIcon.isAsleep(.none))
        #expect(!TabIcon.isAsleep(.reloading))
    }

    /// The dim has to leave room for the moon to read against the favicon.
    @Test func theSleepingFaviconIsDimmedButNotGone() {
        #expect(TabIcon.asleepDim > 0)
        #expect(TabIcon.asleepDim < 1)
    }

    @Test func discardingATabPutsItsFaviconToSleep() {
        let model = BrowserModel(
            database: .temporary(),
            sitePermissions: SitePermissions(
                storageURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("SidebarSleep-\(UUID().uuidString).json")
            )
        )
        let background = model.newTab(url: URL(string: "https://example.com/a"))
        _ = model.newTab(url: URL(string: "https://example.com/b"))

        #expect(!TabIcon.isAsleep(background.reclaimState))
        model.discardBackgroundTabs()
        #expect(TabIcon.isAsleep(background.reclaimState))
    }
}

/// The compact column is narrower than the traffic lights, so its collapse
/// toggle lives in the nav bar beside Back and Forward - the same place the
/// hidden sidebar's copy already stands.
@MainActor
struct SidebarTogglePlacementTests {
    @Test func aHiddenSidebarPutsTheToggleInTheNavBar() {
        #expect(SidebarTogglePlacement.inNavBar(isVisible: false, style: .full))
        #expect(SidebarTogglePlacement.inNavBar(isVisible: false, style: .icons))
    }

    @Test func theIconsColumnHandsItsToggleToTheNavBar() {
        #expect(SidebarTogglePlacement.inNavBar(isVisible: true, style: .icons))
        #expect(!SidebarTogglePlacement.inSidebarTop(style: .icons))
    }

    @Test func theFullSidebarKeepsItsOwnToggle() {
        #expect(!SidebarTogglePlacement.inNavBar(isVisible: true, style: .full))
        #expect(SidebarTogglePlacement.inSidebarTop(style: .full))
    }
}

/// The nav bar's toggle must stand still when clicking it docks or hides the
/// icons column: the content edge moves by the column plus its divider, and
/// the padding has to give back exactly that.
@MainActor
struct SidebarTogglePositionTests {
    private let inset: CGFloat = 84

    private func toggleLeadingEdge(isVisible: Bool, style: SidebarStyle) -> CGFloat {
        let contentStart: CGFloat = isVisible ? SidebarMetrics.iconsWidth + 1 : 0
        let padding = SidebarMetrics.windowControlsPadding(
            isVisible: isVisible,
            style: style,
            windowControlsInset: inset
        )
        return contentStart + padding + 10
    }

    @Test func togglingTheIconsColumnLeavesTheButtonInPlace() {
        let docked = toggleLeadingEdge(isVisible: true, style: .icons)
        let hidden = toggleLeadingEdge(isVisible: false, style: .icons)
        #expect(docked == hidden)
        #expect(docked == inset)
    }

    @Test func thePaddingNeverGoesNegative() {
        for style in [SidebarStyle.full, .icons] {
            for isVisible in [true, false] {
                #expect(SidebarMetrics.windowControlsPadding(
                    isVisible: isVisible,
                    style: style,
                    windowControlsInset: 40
                ) >= 0)
            }
        }
    }
}

/// Hiding slides the column left under the traffic lights; the top controls
/// fade out instead of passing under them. The opacity itself is the seam -
/// the slide is visual.
@MainActor
struct SidebarTopControlsFadeTests {
    @Test func theControlsFadeWithTheColumn() {
        #expect(SidebarMetrics.topControlsOpacity(isShowing: true) == 1)
        #expect(SidebarMetrics.topControlsOpacity(isShowing: false) == 0)
    }
}

/// The icons rail's drag chip stays at the row's own size; only the full
/// row's copy takes the slight lift.
@MainActor
struct SidebarDragGhostTests {
    @Test func theIconsChipIsNotScaled() {
        #expect(SidebarDragGhost.liftScale(style: .icons) == 1)
    }

    @Test func theFullRowChipLiftsSlightly() {
        #expect(SidebarDragGhost.liftScale(style: .full) > 1)
        #expect(SidebarDragGhost.liftScale(style: .full) < 1.1)
    }

    @Test func theChipShowsWhatIsUnderneath() {
        #expect(SidebarDragGhost.chipFillOpacity < 0.72)
        #expect(SidebarDragGhost.chipFillOpacity > 0.3)
    }
}

/// The toggle's right-click menu drives the same stored style Settings does.
@MainActor
struct SidebarIconsOnlyMenuTests {
    private func makeLayout() -> (SidebarLayout, UserDefaults, String) {
        let suite = "SidebarIconsOnlyMenuTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (SidebarLayout(defaults: defaults), defaults, suite)
    }

    @Test func togglingIconsOnlySwitchesAndPersistsTheStyle() {
        let (layout, defaults, suite) = makeLayout()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(!layout.isIconsOnly)
        layout.setIconsOnly(true)
        #expect(layout.isIconsOnly)
        #expect(layout.style == .icons)
        #expect(SidebarLayout(defaults: defaults).style == .icons)

        layout.setIconsOnly(false)
        #expect(!layout.isIconsOnly)
        #expect(layout.style == .full)
        #expect(layout.openWidth(in: 1000) >= SidebarMetrics.minWidth)
    }
}

/// While the hidden sidebar is peeked out over the page, the page under it
/// must not react to the pointer. WebKit's hover tracking areas are owned by
/// its private observer - never the view - so the shield unregisters them
/// rather than filtering events that would never pass through the view.
@MainActor
@Suite(.boundedWebViews)
struct SidebarPeekShieldTests {
    private let width: CGFloat = 268
    private let pageMaxX: CGFloat = 1200

    @Test func aPeekedSidebarSuppressesThePagesHover() {
        #expect(SidebarPeekShield.suppressesHover(
            isVisible: false, isPeeking: true, viewMaxX: pageMaxX, width: width,
            isMediaPicture: false
        ))
    }

    @Test func aDockedSidebarShieldsNothing() {
        #expect(!SidebarPeekShield.suppressesHover(
            isVisible: true, isPeeking: false, viewMaxX: pageMaxX, width: width,
            isMediaPicture: false
        ))
    }

    @Test func aHiddenUnpeekedSidebarShieldsNothing() {
        #expect(!SidebarPeekShield.suppressesHover(
            isVisible: false, isPeeking: false, viewMaxX: pageMaxX, width: width,
            isMediaPicture: false
        ))
    }

    /// A web view inside the column is part of the sidebar, not under it.
    @Test func aViewInsideTheStripIsNotShieldedFromItself() {
        #expect(!SidebarPeekShield.suppressesHover(
            isVisible: false, isPeeking: true, viewMaxX: 48, width: width,
            isMediaPicture: false
        ))
    }

    @Test func theMediaCardsPictureIsAlwaysShielded() {
        #expect(SidebarPeekShield.suppressesHover(
            isVisible: true, isPeeking: false, viewMaxX: 48, width: width,
            isMediaPicture: true
        ))
        #expect(SidebarPeekShield.suppressesHover(
            isVisible: false, isPeeking: false, viewMaxX: pageMaxX, width: width,
            isMediaPicture: true
        ))
    }

    /// The mechanism itself: parking removes every tracking area WebKit owns
    /// (AppKit cannot deliver to an unregistered area), keeps areas added
    /// mid-park off the view, and restores the very same instances after.
    @Test func parkingUnregistersWebKitsTrackingAreasAndRestoresThem() async throws {
        let web = TabWebView(
            frame: NSRect(x: 0, y: 0, width: 600, height: 400),
            configuration: WKWebViewConfiguration()
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        window.contentView?.addSubview(web)
        web.loadHTMLString("<html><body>page</body></html>", baseURL: nil)

        var foreign: [NSTrackingArea] = []
        _ = await waitUntil {
            foreign = web.trackingAreas.filter { $0.owner !== web }
            return !foreign.isEmpty
        }
        try #require(!foreign.isEmpty)

        web.setHoverParked(true)
        #expect(web.trackingAreas.allSatisfy { $0.owner === web })

        let lateOwner = NSObject()
        let late = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeInKeyWindow],
            owner: lateOwner,
            userInfo: nil
        )
        web.addTrackingArea(late)
        #expect(!web.trackingAreas.contains { $0 === late })

        web.setHoverParked(false)
        for area in foreign {
            #expect(web.trackingAreas.contains { $0 === area })
        }
        #expect(web.trackingAreas.contains { $0 === late })
    }
}

/// The row says its key out loud, the way the palette does.
@MainActor
struct NewTabShortcutHintTests {
    @Test func theHintIsCommandT() {
        #expect(NewTabRow.shortcutHint == "⌘T")
    }
}

/// Folding a drag with a grid row must take the whole grid: the leader alone
/// would leave its followers stranded outside the folder.
@MainActor
struct SplitFoldCommitTests {
    @Test func aGridLeaderStandsForAllItsMembers() {
        let model = BrowserModel(
            database: .temporary(),
            sitePermissions: SitePermissions(
                storageURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("SplitFoldCommit-\(UUID().uuidString).json")
            )
        )
        let a = model.newTab(url: URL(string: "https://example.com/a"))
        let b = model.newTab(url: URL(string: "https://example.com/b"))
        let c = model.newTab(url: URL(string: "https://example.com/c"))
        model.split(a, with: b, axis: .sideBySide)

        let members = model.withSplitMembers([.tab(a.id)])
        #expect(Set(members) == [.tab(a.id), .tab(b.id)])

        let folder = model.createFolder(containing: members + [.tab(c.id)])
        #expect(Set(model.rows(in: folder)) == [.tab(a.id), .tab(b.id), .tab(c.id)])
    }

    /// A split pane draws its own row content, and carried its own inset, so
    /// its favicon and title sat left of every single-tab row around it.
    @Test func splitAndSingleRowsShareTheirContentInset() {
        #expect(SidebarMetrics.rowContentPadding(style: .full) == 9)
        #expect(SidebarMetrics.rowContentPadding(style: .icons) == 0)
        #expect(SidebarMetrics.rowIconSize == 16)
        #expect(SidebarMetrics.rowIconSpacing == 8)
    }
}
