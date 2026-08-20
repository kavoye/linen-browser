// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

/// Giving WebContent processes back when the system asks. The contract: the
/// tab survives as a row, the page comes back from its stored session, and
/// nothing the user is looking at or listening to is taken away.
@MainActor
@Suite(.boundedWebViews)
struct TabDiscardTests {
    private func makeModel(permissions: SitePermissions? = nil) -> BrowserModel {
        BrowserModel(database: .temporary(), sitePermissions: permissions ?? makePermissions())
    }

    private func makePermissions() -> SitePermissions {
        SitePermissions(
            storageURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("TabDiscardPermissions-\(UUID().uuidString).json")
        )
    }

    /// A discarded tab is in the same state as a restored-but-unopened one:
    /// it keeps its row and reloads on activation.
    @Test func aDiscardedTabKeepsItsRowAndBecomesDeferred() {
        let model = makeModel()
        let background = model.newTab(url: URL(string: "https://example.com/a"))
        background.title = "Somewhere"
        _ = model.newTab(url: URL(string: "https://example.com/b"))

        #expect(background.canDiscardWebContent)
        model.discardBackgroundTabs()

        #expect(background.isDeferred)
        #expect(background.title == "Somewhere")
        #expect(background.urlString == "https://example.com/a")
        #expect(model.tabs.contains { $0 === background })
    }

    /// The view is replaced, not emptied - that is what hands the process
    /// back. Anything drawing the tab has to be told, so it is observable.
    @Test func discardingReplacesTheWebView() {
        let model = makeModel()
        let background = model.newTab(url: URL(string: "https://example.com/a"))
        _ = model.newTab(url: URL(string: "https://example.com/b"))
        let before = background.webView

        model.discardBackgroundTabs()

        #expect(background.webView !== before)
        // And the outgoing view is not left parented anywhere, which would
        // keep it - and its process - alive for the life of the window.
        #expect(before.superview == nil)
    }

    @Test func theActiveTabIsNeverDiscarded() {
        let model = makeModel()
        _ = model.newTab(url: URL(string: "https://example.com/a"))
        let active = model.newTab(url: URL(string: "https://example.com/b"))

        #expect(model.activeTabID == active.id)
        model.discardBackgroundTabs()

        #expect(!active.isDeferred)
    }

    /// Discarding one would write its page into a store meant to die with it,
    /// and reloading it later would be a second visit to a site the user
    /// asked the browser to forget.
    @Test func aPrivateTabIsNeverDiscarded() {
        let model = makeModel()
        model.adopt(
            database: .temporary(),
            sitePermissions: makePermissions(),
            privately: true
        )
        let priv = model.newTab(url: URL(string: "https://example.com/a"))
        _ = model.newTab(url: URL(string: "https://example.com/b"))

        #expect(priv.isPrivate)
        #expect(!priv.canDiscardWebContent)
        model.discardBackgroundTabs()
        #expect(!priv.isDeferred)
    }

    /// Taking the view away takes the sound with it.
    @Test func anAudibleTabIsNeverDiscarded() {
        let model = makeModel()
        let playing = model.newTab(url: URL(string: "https://example.com/a"))
        playing.isPlayingAudio = true
        _ = model.newTab(url: URL(string: "https://example.com/b"))

        #expect(!playing.canDiscardWebContent)
        model.discardBackgroundTabs()
        #expect(!playing.isDeferred)
    }

    /// The media card is this tab's remote; discarding the tab kills it.
    @Test func aTabControlledByTheMediaDockIsNeverDiscarded() {
        let model = makeModel()
        let lent = model.newTab(url: URL(string: "https://example.com/a"))
        lent.isControlledByMediaDock = true
        _ = model.newTab(url: URL(string: "https://example.com/b"))

        #expect(!lent.canDiscardWebContent)
    }

    /// A gentle warning spares the few tabs the user is moving between, so
    /// ⌃Tab back and forth doesn't reload.
    @Test func aWarningSparesTheMostRecentlyUsedTabs() {
        let model = makeModel()
        let oldest = model.newTab(url: URL(string: "https://example.com/1"))
        let recent = model.newTab(url: URL(string: "https://example.com/2"))
        let active = model.newTab(url: URL(string: "https://example.com/3"))

        // Visited in order, so `recent` is the last background tab touched.
        model.activate(oldest)
        model.activate(recent)
        model.activate(active)

        model.relieveMemoryPressure(.warning)

        #expect(!active.isDeferred)
        #expect(!recent.isDeferred)
        #expect(!oldest.isDeferred)
    }

    /// Critical means the app is about to be killed, so recency stops earning
    /// anything.
    @Test func criticalPressureTakesEveryBackgroundTab() {
        let model = makeModel()
        let first = model.newTab(url: URL(string: "https://example.com/1"))
        let second = model.newTab(url: URL(string: "https://example.com/2"))
        let active = model.newTab(url: URL(string: "https://example.com/3"))
        model.activate(first)
        model.activate(second)
        model.activate(active)

        model.relieveMemoryPressure(.critical)

        #expect(first.isDeferred)
        #expect(second.isDeferred)
        #expect(!active.isDeferred)
    }

    /// Activating a discarded tab is what brings it back, through the same
    /// path a restored session uses.
    @Test func activatingADiscardedTabRealizesItAgain() {
        let model = makeModel()
        let background = model.newTab(url: URL(string: "https://example.com/a"))
        _ = model.newTab(url: URL(string: "https://example.com/b"))
        model.discardBackgroundTabs()
        #expect(background.isDeferred)

        model.activate(background)

        #expect(!background.isDeferred)
    }

    /// Discarding twice must not throw away the session the first one stored.
    @Test func aTabAlreadyDiscardedIsLeftAlone() {
        let model = makeModel()
        let background = model.newTab(url: URL(string: "https://example.com/a"))
        _ = model.newTab(url: URL(string: "https://example.com/b"))

        model.discardBackgroundTabs()
        let view = background.webView
        #expect(!background.canDiscardWebContent)

        model.discardBackgroundTabs()
        #expect(background.webView === view)
        #expect(background.urlString == "https://example.com/a")
    }

    /// A blank tab has nothing to come back to, and costs nothing to keep.
    @Test func aBlankTabIsNotWorthDiscarding() {
        let model = makeModel()
        let blank = model.newTab()
        _ = model.newTab(url: URL(string: "https://example.com/b"))

        #expect(!blank.canDiscardWebContent)
    }

    @Test func anEditedFormIsNeverDiscarded() {
        let model = makeModel()
        let form = model.newTab(url: URL(string: "https://example.com/form"))
        _ = model.newTab(url: URL(string: "https://example.com/other"))
        form.notePageActivity(.init(kind: .editedForm, token: "main", isActive: true))

        model.discardBackgroundTabs()

        #expect(!form.isDeferred)
        #expect(model.protectionReason(for: form) == .editedForm)
    }

    @Test func aScreenShareIsNeverDiscarded() {
        let model = makeModel()
        let sharing = model.newTab(url: URL(string: "https://example.com/call"))
        _ = model.newTab(url: URL(string: "https://example.com/other"))
        sharing.notePageActivity(.init(kind: .screenShare, token: "main", isActive: true))

        model.discardBackgroundTabs()

        #expect(!sharing.isDeferred)
        #expect(model.protectionReason(for: sharing) == .deviceAccess)

        sharing.notePageActivity(.init(kind: .screenShare, token: "main", isActive: false))
        model.discardBackgroundTabs()
        #expect(sharing.isDeferred)
    }

    @Test func aTabUsingADeviceIsNeverDiscarded() {
        let model = makeModel()
        let recording = model.newTab(url: URL(string: "https://example.com/call"))
        _ = model.newTab(url: URL(string: "https://example.com/other"))
        recording.permissions.setLive(.microphone, true)

        model.discardBackgroundTabs()
        #expect(!recording.isDeferred)

        recording.permissions.setLive(.microphone, false)
        model.discardBackgroundTabs()
        #expect(recording.isDeferred)
    }

    @Test func aTabWithAgentWorkIsNeverDiscarded() {
        let model = makeModel()
        let working = model.newTab(url: URL(string: "https://example.com/task"))
        _ = model.newTab(url: URL(string: "https://example.com/other"))
        working.setAgentWorking(true)

        model.discardBackgroundTabs()
        #expect(!working.isDeferred)

        working.setAgentWorking(false)
        model.discardBackgroundTabs()
        #expect(working.isDeferred)
    }

    @Test func aTabWithAnActiveDownloadIsNeverDiscarded() {
        let model = makeModel()
        let downloading = model.newTab(url: URL(string: "https://example.com/file"))
        _ = model.newTab(url: URL(string: "https://example.com/other"))
        let downloadID = model.downloads.beginItem(
            source: URL(string: "https://example.com/file.zip"),
            sourceTabID: downloading.id
        )

        model.discardBackgroundTabs()
        #expect(!downloading.isDeferred)
        #expect(model.protectionReason(for: downloading) == .activeDownload)

        model.downloads.noteFailure(downloadID, reason: "Stopped", resumeData: nil)
        model.discardBackgroundTabs()
        #expect(downloading.isDeferred)
    }

    @Test func anAlwaysActiveWebsiteIsNeverDiscarded() {
        let permissions = makePermissions()
        let model = makeModel(permissions: permissions)
        let kept = model.newTab(url: URL(string: "https://example.com/page"))
        _ = model.newTab(url: URL(string: "https://other.example/page"))
        model.setKeepsActive(true, for: kept)

        model.discardBackgroundTabs()

        #expect(!kept.isDeferred)
        #expect(model.protectionReason(for: kept) == .alwaysKeepActive)
        #expect(permissions.keptActiveOrigins == ["https://example.com"])
    }

    @Test func anUnloadedTabSaysSoUntilTheReloadStarts() {
        let model = makeModel()
        let background = model.newTab(url: URL(string: "https://example.com/a"))
        _ = model.newTab(url: URL(string: "https://example.com/b"))

        model.discardBackgroundTabs()
        #expect(background.reclaimState == .unloaded)

        model.activate(background)
        #expect(background.reclaimState == .reloading)
    }
}
