// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
import WebKit

@testable import Linen

@MainActor
struct LoomChromeTests {
    @Test func siteColourIsPresentButConstrained() throws {
        let source = NSColor(srgbRed: 1, green: 0.16, blue: 0, alpha: 1)
        let sampled = try #require(
            LoomChrome.sampledColor(source, scheme: .light).usingColorSpace(.sRGB)
        )

        #expect(sampled.redComponent > sampled.greenComponent)
        #expect(sampled.greenComponent > source.greenComponent)
        #expect(sampled.redComponent < 1)
    }

    @Test func anAchromaticPageStillSetsTheLoomsTone() throws {
        let black = try #require(
            LoomChrome.sampledColor(.black, scheme: .light).usingColorSpace(.sRGB)
        )
        let white = try #require(
            LoomChrome.sampledColor(.white, scheme: .dark).usingColorSpace(.sRGB)
        )

        #expect(black.brightnessComponent < 0.2)
        #expect(white.brightnessComponent > 0.8)
    }

    @Test func aDarkColouredPageCanSetADarkAppearance() throws {
        let navy = NSColor(srgbRed: 0.02, green: 0.05, blue: 0.35, alpha: 1)
        let tinted = try #require(
            LoomChrome.sampledColor(navy, scheme: .light).usingColorSpace(.sRGB)
        )
        let plain = try #require(
            LoomChrome.sampledColor(nil, scheme: .light).usingColorSpace(.sRGB)
        )

        #expect(tinted.blueComponent > tinted.redComponent)
        #expect(tinted.brightnessComponent < plain.brightnessComponent)
        #expect(tinted.brightnessComponent < 0.4)
    }

    @Test func canvasUsesOneTightGapAfterTheToolbar() {
        #expect(LoomChrome.canvasTop == Theme.topBarHeight + 3)
        #expect(LoomChrome.canvasGap < LoomChrome.canvasInset)
    }

    /// One radius on every corner, and the same shape for the lens as for the
    /// clip: glass returns a straight edge for any rectangle it cannot name,
    /// which an uneven one is.
    @Test func theCanvasCarriesOneRadiusAllRound() {
        #expect(LoomChrome.canvasShape.cornerSize.width == LoomChrome.canvasRadius)
        #expect(LoomChrome.canvasShape.cornerSize.height == LoomChrome.canvasRadius)
        #expect(LoomChrome.canvasShape.style == .continuous)
    }

    /// A page only reflows to its narrow layout when the view it is in gets
    /// narrow. The window's own floor is what decides whether it ever can.
    @Test func theWindowNarrowsFarEnoughForAPageToReflow() {
        let commonNarrowBreakpoint: CGFloat = 768
        let barestCanvas = BrowserWindowMetrics.minWidth - LoomChrome.canvasInset * 2

        #expect(barestCanvas < commonNarrowBreakpoint)
        #expect(BrowserWindowMetrics.minWidth - SidebarMetrics.minWidth > 0)
    }

    @Test func theCanvasRunsParallelToTheWindow() {
        #expect(LoomChrome.canvasRadius == Theme.Radius.window - LoomChrome.canvasInset)
    }

    @Test func sidePanelAndResizeGutterShareShellGeometry() {
        let shell = LoomShellGeometry(
            containerWidth: 1_200,
            sidebarWidth: 268,
            preferredPanelWidth: 320,
            isSidebarVisible: true,
            isPanelVisible: true,
            isPanelExpanded: false
        )

        #expect(shell.panelWidth == 320)
        #expect(shell.canvasTrailingInset == 320 + LoomChrome.canvasInset)
        let resizeCenter = shell.sidebarResizeLeading + LoomChrome.resizeGrabWidth / 2
        #expect(resizeCenter == 268 + LoomChrome.canvasInset / 2)
    }

    /// The bug: WebKit's tracking areas do not hit-test against what covers
    /// them, so a page reaching under the panel kept answering the pointer.
    @Test func aPageReachingUnderThePanelIsCovered() {
        let shell = LoomShellGeometry(
            containerWidth: 1_200,
            sidebarWidth: 0,
            preferredPanelWidth: 320,
            isSidebarVisible: false,
            isPanelVisible: true,
            isPanelExpanded: false
        )

        #expect(!shell.panelCoversPage(viewMaxX: shell.panelLeading - LoomChrome.canvasInset))
        #expect(shell.panelCoversPage(viewMaxX: 1_200))
    }

    @Test func aClosedPanelCoversNothing() {
        let shell = LoomShellGeometry(
            containerWidth: 1_200,
            sidebarWidth: 0,
            preferredPanelWidth: 320,
            isSidebarVisible: false,
            isPanelVisible: false,
            isPanelExpanded: false
        )

        #expect(!shell.panelCoversPage(viewMaxX: 1_200))
    }

    @Test func expandedPanelStaysInsideBothCanvasEdges() {
        let shell = LoomShellGeometry(
            containerWidth: 1_200,
            sidebarWidth: 268,
            preferredPanelWidth: 320,
            isSidebarVisible: true,
            isPanelVisible: true,
            isPanelExpanded: true
        )

        #expect(shell.panelWidth == 1_200 - 268 - LoomChrome.canvasInset * 2)
        #expect(shell.canvasTrailingInset == 0)
    }
}

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

/// The sidebar toggle belongs to the window beam, never to the sidebar or a
/// particular toolbar variant. Content controls only reserve its fixed slot.
@MainActor
struct SidebarPermanentToggleTests {
    private let inset: CGFloat = 84
    private let contentInset: CGFloat = 10

    private func firstContentControl(
        isVisible: Bool,
        style: SidebarStyle,
        sidebarWidth: CGFloat = SidebarMetrics.defaultWidth
    ) -> CGFloat {
        let contentStart: CGFloat
        if !isVisible {
            contentStart = 0
        } else {
            contentStart = style == .icons ? SidebarMetrics.iconsWidth : sidebarWidth
        }
        let padding = SidebarMetrics.toolbarLeadingPadding(
            isVisible: isVisible,
            style: style,
            windowControlsInset: inset,
            contentInset: contentInset
        )
        return contentStart + padding + contentInset
    }

    @Test func theWindowOwnedToggleHasOneStableLeadingEdge() {
        #expect(SidebarMetrics.permanentToggleLeading(windowControlsInset: inset) == inset)
        #expect(SidebarMetrics.permanentToggleLeading(windowControlsInset: 0) == 10)
    }

    @Test func hiddenAndIconsLayoutsClearTheSamePermanentControl() {
        let hidden = firstContentControl(isVisible: false, style: .full)
        let icons = firstContentControl(isVisible: true, style: .icons)
        let toggleTrailing = inset + SidebarMetrics.permanentToggleSlot

        #expect(hidden == toggleTrailing)
        #expect(icons == toggleTrailing)
    }

    @Test func aFullSidebarAlreadyPlacesContentPastTheToggle() {
        let leading = firstContentControl(isVisible: true, style: .full)

        #expect(leading == SidebarMetrics.defaultWidth + contentInset)
        #expect(leading > inset + SidebarMetrics.permanentToggleSlot)
    }

    @Test func thePaddingNeverGoesNegative() {
        for style in [SidebarStyle.full, .icons] {
            for isVisible in [true, false] {
                #expect(SidebarMetrics.toolbarLeadingPadding(
                    isVisible: isVisible,
                    style: style,
                    windowControlsInset: 40,
                    contentInset: contentInset
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

/// The bug: profile, downloads and the bug report were pinned to a square in
/// the compact column while tabs and Settings filled it, so their hover shape
/// and click target were narrower than everything above them.
@MainActor
struct SidebarTrayControlWidthTests {
    private var compactContentWidth: CGFloat {
        SidebarMetrics.iconsWidth - SidebarMetrics.contentInset(style: .icons) * 2
    }

    @Test func everyCompactControlFillsTheColumn() {
        #expect(SidebarMetrics.controlMaxWidth(style: .icons) == .infinity)
    }

    /// A full sidebar lays them out side by side, where filling would give the
    /// first control the whole row.
    @Test func aFullSidebarKeepsThemSquare() {
        #expect(SidebarMetrics.controlMaxWidth(style: .full) == SidebarMetrics.controlHeight)
    }

    @Test func theCompactColumnIsWiderThanTheSquareTheyHeldTo() {
        #expect(compactContentWidth > SidebarMetrics.controlHeight)
    }
}
