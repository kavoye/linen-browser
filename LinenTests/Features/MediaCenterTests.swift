// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Testing
import WebKit

@testable import Linen

/// Which tab is controlled, which view is lent, and where the crop lands.
@MainActor
@Suite(.serialized, .boundedWebViews)
struct MediaCenterTests {
    private func lend(_ media: MediaCenter, _ webView: WKWebView, tabID: UUID) {
        media.controlTab(webView: webView, title: "Playing", tabID: tabID, artwork: nil)
        media.model.pictureWebView = webView
    }

    @Test func takingOverAnotherTabDropsTheFirstPicture() {
        let media = MediaCenter()
        var changes: [[UUID?]] = []
        media.onControlledTabChanged = { changes.append([$0, $1]) }
        let first = WKWebView()
        let second = WKWebView()
        let firstID = UUID()
        let secondID = UUID()

        lend(media, first, tabID: firstID)
        media.model.playerViewportRect = CGRect(x: 0, y: 0, width: 640, height: 360)
        media.controlTab(webView: second, title: "Playing", tabID: secondID, artwork: nil)

        #expect(changes == [[nil, firstID], [firstID, secondID]])
        #expect(media.model.pictureWebView == nil)
        #expect(media.model.playerViewportRect == nil)
    }

    @Test func releasingControlDropsThePicture() {
        let media = MediaCenter()
        var changes: [[UUID?]] = []
        media.onControlledTabChanged = { changes.append([$0, $1]) }
        let webView = WKWebView()
        let tabID = UUID()

        lend(media, webView, tabID: tabID)
        media.model.playerViewportRect = CGRect(x: 0, y: 0, width: 640, height: 360)
        media.releaseControl()

        #expect(changes == [[nil, tabID], [tabID, nil]])
        #expect(media.model.pictureWebView == nil)
        #expect(media.model.playerViewportRect == nil)
    }

    @Test func rectReportFromTheControlledMainFramePlacesThePlayer() {
        let media = MediaCenter()
        let webView = WKWebView()
        lend(media, webView, tabID: UUID())

        media.receiveScriptMessage(
            "rect:{\"x\":10,\"y\":20,\"w\":640,\"h\":360}",
            from: webView,
            isMainFrame: true
        )

        #expect(media.model.playerViewportRect == CGRect(x: 10, y: 20, width: 640, height: 360))
    }

    @Test func rectReportsFromSubframesAndOtherTabsAreIgnored() {
        let media = MediaCenter()
        let webView = WKWebView()
        let other = WKWebView()
        lend(media, webView, tabID: UUID())

        media.receiveScriptMessage(
            "rect:{\"x\":1,\"y\":2,\"w\":300,\"h\":200}",
            from: webView,
            isMainFrame: false
        )
        media.receiveScriptMessage(
            "rect:{\"x\":1,\"y\":2,\"w\":300,\"h\":200}",
            from: other,
            isMainFrame: true
        )

        #expect(media.model.playerViewportRect == nil)
    }

    @Test func emptyRectReportClearsThePlacement() {
        let media = MediaCenter()
        let webView = WKWebView()
        lend(media, webView, tabID: UUID())

        media.receiveScriptMessage(
            "rect:{\"x\":0,\"y\":0,\"w\":640,\"h\":360}",
            from: webView,
            isMainFrame: true
        )
        media.receiveScriptMessage("rect:", from: webView, isMainFrame: true)

        #expect(media.model.playerViewportRect == nil)
    }

    @Test func zeroSizedAndMalformedRectsChangeNothing() {
        let media = MediaCenter()
        let webView = WKWebView()
        lend(media, webView, tabID: UUID())
        let placed = CGRect(x: 0, y: 0, width: 640, height: 360)
        media.receiveScriptMessage(
            "rect:{\"x\":0,\"y\":0,\"w\":640,\"h\":360}",
            from: webView,
            isMainFrame: true
        )

        media.receiveScriptMessage(
            "rect:{\"x\":0,\"y\":0,\"w\":0,\"h\":360}",
            from: webView,
            isMainFrame: true
        )
        media.receiveScriptMessage("rect:not json", from: webView, isMainFrame: true)

        #expect(media.model.playerViewportRect == placed)
    }

    @Test func stateWithAPictureLendsTheControlledView() {
        let media = MediaCenter()
        let webView = WKWebView()
        media.controlTab(webView: webView, title: "Playing", tabID: UUID(), artwork: nil)

        media.receiveScriptMessage(
            "state:{\"t\":1,\"d\":100,\"l\":0,\"p\":1,\"v\":1,\"m\":0,\"w\":1280}",
            from: webView,
            isMainFrame: true
        )

        #expect(media.model.pictureWebView === webView)
    }

    /// Read from a view body, so it has to live on the observable model: off
    /// `MediaCenter` the menu's tick stayed on the tab the dock had left.
    @Test func theDockedTabIsObservable() {
        let media = MediaCenter()
        let first = UUID()
        let second = UUID()

        media.controlTab(webView: WKWebView(), title: "One", tabID: first, artwork: nil)
        #expect(media.model.controlledTabID == first)
        #expect(media.controlledTabID == first)

        media.controlTab(webView: WKWebView(), title: "Two", tabID: second, artwork: nil)
        #expect(media.model.controlledTabID == second)
        #expect(media.controlledTabID == second)

        media.releaseControl()
        #expect(media.model.controlledTabID == nil)
        #expect(media.controlledTabID == nil)
    }

    @Test func stateWithoutAPictureLendsNothing() {
        let media = MediaCenter()
        let webView = WKWebView()
        media.controlTab(webView: webView, title: "Playing", tabID: UUID(), artwork: nil)

        media.receiveScriptMessage(
            "state:{\"t\":1,\"d\":100,\"l\":0,\"p\":1,\"v\":1,\"m\":0,\"w\":0}",
            from: webView,
            isMainFrame: true
        )

        #expect(media.model.pictureWebView == nil)
    }
}

/// The script's own reporting, against a real web view.
@MainActor
@Suite(.serialized, .boundedWebViews)
struct MediaScriptRectTests {
    private final class Collector: NSObject, WKScriptMessageHandler {
        var messages: [String] = []

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            messages.append(message.body as? String ?? "")
        }
    }

    private func playerWebView() async -> (WKWebView, Collector) {
        let collector = Collector()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(
            collector,
            name: MediaCenter.frameScriptHandlerName
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: MediaCenter.frameScriptSource,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
        )
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
        webView.loadHTMLString(
            """
            <!doctype html><html><body style="margin:0">
            <video style="width:640px;height:360px"></video>
            </body></html>
            """,
            baseURL: nil
        )
        #expect(await PageSettle.untilIdle(webView, timeout: .seconds(30)))
        return (webView, collector)
    }

    private func waitForRect(_ collector: Collector) async -> String? {
        for _ in 0..<100 {
            if let rect = collector.messages.last(where: { $0.hasPrefix("rect:") }) {
                return rect
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    @Test func thePlayerRectIsReported() async {
        let (_, collector) = await playerWebView()

        let rect = await waitForRect(collector)

        #expect(rect?.contains("\"w\":640") == true)
        #expect(rect?.contains("\"h\":360") == true)
    }

    @Test func revealReportsTheRectAgainAfterItWasAlreadyPosted() async {
        let (webView, collector) = await playerWebView()
        _ = await waitForRect(collector)
        collector.messages.removeAll()

        _ = try? await webView.evaluateJavaScript("window.postMessage('linen-reveal', '*')")

        let rect = await waitForRect(collector)
        #expect(rect?.contains("\"w\":640") == true)
    }
}

struct MediaRosterTests {
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()

    @Test func aPlayingBackgroundTabIsACandidate() {
        #expect(MediaRoster.isCandidate(
            isPlayingAudio: true,
            isMuted: false,
            isInternalPage: false,
            isActive: false,
            isVisibleInSplit: false,
            isDocked: false
        ))
    }

    @Test func whatTheDockCannotDriveIsNotACandidate() {
        func candidate(
            active: Bool = false,
            muted: Bool = false,
            internalPage: Bool = false,
            visibleInSplit: Bool = false
        ) -> Bool {
            MediaRoster.isCandidate(
                isPlayingAudio: true,
                isMuted: muted,
                isInternalPage: internalPage,
                isActive: active,
                isVisibleInSplit: visibleInSplit,
                isDocked: false
            )
        }

        #expect(!candidate(active: true))
        #expect(!candidate(muted: true))
        #expect(!candidate(internalPage: true))
        #expect(!candidate(visibleInSplit: true))
    }

    @Test func theDockedTabKeepsItsPlaceWhilePaused() {
        #expect(MediaRoster.isCandidate(
            isPlayingAudio: false,
            isMuted: false,
            isInternalPage: false,
            isActive: false,
            isVisibleInSplit: false,
            isDocked: true
        ))
    }

    /// Muting a tab used to hand the dock to the next tab, and the media card
    /// went with it. Mute silences the tab; it does not undock it.
    @Test func theDockedTabKeepsItsPlaceWhileMuted() {
        #expect(MediaRoster.isCandidate(
            isPlayingAudio: true,
            isMuted: true,
            isInternalPage: false,
            isActive: false,
            isVisibleInSplit: false,
            isDocked: true
        ))
    }

    @Test func aPausedTabThatIsNotDockedIsNotACandidate() {
        #expect(!MediaRoster.isCandidate(
            isPlayingAudio: false,
            isMuted: false,
            isInternalPage: false,
            isActive: false,
            isVisibleInSplit: false,
            isDocked: false
        ))
    }

    private func pickerItem(
        playing: Bool = false,
        muted: Bool = false,
        internalPage: Bool = false,
        active: Bool = false,
        visibleInSplit: Bool = false,
        docked: Bool = false,
        hasPlayed: Bool = false
    ) -> Bool {
        MediaRoster.isPickerItem(
            isPlayingAudio: playing,
            isMuted: muted,
            isInternalPage: internalPage,
            isActive: active,
            isVisibleInSplit: visibleInSplit,
            isDocked: docked,
            hasPlayed: hasPlayed
        )
    }

    /// Pausing a tab and moving on used to strand it: silent and undocked, it
    /// left the picker and could only be reached from the sidebar again.
    @Test func aTabThatPlayedAndFellQuietStaysInThePicker() {
        #expect(pickerItem(hasPlayed: true))
        #expect(!pickerItem(hasPlayed: false))
    }

    @Test func theDockedTabStaysInItsOwnPickerWhileMuted() {
        #expect(pickerItem(playing: true, muted: true, docked: true))
    }

    @Test func havingPlayedDoesNotOverrideWhatTheDockCannotDrive() {
        #expect(!pickerItem(muted: true, hasPlayed: true))
        #expect(!pickerItem(internalPage: true, hasPlayed: true))
        #expect(!pickerItem(active: true, hasPlayed: true))
        #expect(!pickerItem(visibleInSplit: true, hasPlayed: true))
    }

    @Test func whatIsPlayingIsInThePickerWhetherItPlayedBeforeOrNot() {
        #expect(pickerItem(playing: true, hasPlayed: false))
        #expect(pickerItem(docked: true, hasPlayed: false))
    }

    @Test func theSuccessorIsTheNextTabDownTheList() {
        #expect(MediaRoster.successor(to: a, in: [a, b, c]) == b)
        #expect(MediaRoster.successor(to: c, in: [a, b, c]) == a)
    }

    @Test func aTabAlreadyGoneHandsOverToTheTopOfTheList() {
        #expect(MediaRoster.successor(to: a, in: [b, c]) == b)
    }

    @Test func thereIsNoSuccessorWhenNothingElsePlays() {
        #expect(MediaRoster.successor(to: a, in: [a]) == nil)
        #expect(MediaRoster.successor(to: a, in: []) == nil)
    }
}

/// The card's picture takes no pointer input at all.
@MainActor
@Suite(.boundedWebViews)
struct MediaCropSurfaceTests {
    @Test func theCropSurfaceRefusesEveryHitTest() {
        let container = MediaCropContainer()
        container.frame = NSRect(x: 0, y: 0, width: 276, height: 155)
        container.crop = CGRect(x: 0, y: 0, width: 640, height: 360)

        #expect(container.hitTest(NSPoint(x: 138, y: 77)) == nil)
        #expect(container.hitTest(NSPoint(x: 0, y: 0)) == nil)
    }

    @Test func lendingAndReturningThePictureAsksForTheShield() {
        let media = MediaCenter()
        var asked = 0
        media.onPictureChanged = { asked += 1 }
        let webView = WKWebView()
        media.controlTab(webView: webView, title: "Playing", tabID: UUID(), artwork: nil)

        media.receiveScriptMessage(
            "state:{\"t\":1,\"d\":100,\"l\":0,\"p\":1,\"v\":1,\"m\":0,\"w\":1280}",
            from: webView,
            isMainFrame: true
        )
        #expect(asked == 1)

        media.releaseControl()
        #expect(asked == 2)
    }
}

/// The timeline row always holds something; it never goes blank.
struct MediaTimelineFaceTests {
    @Test func aLengthThatHasNotArrivedShowsThePendingRowRatherThanNothing() {
        #expect(
            MediaTimelineFace.face(isLive: false, currentTime: 0, duration: 0)
                == .pending(elapsed: 0)
        )
    }

    @Test func theBeatAfterTheDockChangesTabsIsPending() {
        let model = MediaModel()
        #expect(
            MediaTimelineFace.face(
                isLive: model.isLive,
                currentTime: model.currentTime,
                duration: model.duration
            ) == .pending(elapsed: 0)
        )
    }

    @Test func aBufferingVideoKeepsTheTimeItHasPlayed() {
        #expect(
            MediaTimelineFace.face(isLive: false, currentTime: 42, duration: 0)
                == .pending(elapsed: 42)
        )
    }

    @Test func aKnownLengthShowsTheScrubber() {
        #expect(
            MediaTimelineFace.face(isLive: false, currentTime: 30, duration: 120)
                == .scrubber(elapsed: 30, remaining: 90, progress: 0.25)
        )
    }

    @Test func aStreamHasNoRowAtAllHoweverItReportsItself() {
        #expect(MediaTimelineFace.face(isLive: true, currentTime: 0, duration: 0) == .live)
        #expect(MediaTimelineFace.face(isLive: true, currentTime: 500, duration: 0) == .live)
        #expect(MediaTimelineFace.face(isLive: true, currentTime: 500, duration: 900) == .live)
    }

    @Test func timesPastTheEndAreHeldInsideTheRow() {
        #expect(
            MediaTimelineFace.face(isLive: false, currentTime: 130, duration: 120)
                == .scrubber(elapsed: 130, remaining: 0, progress: 1)
        )
        #expect(
            MediaTimelineFace.face(isLive: false, currentTime: -5, duration: 120)
                == .scrubber(elapsed: 0, remaining: 120, progress: 0)
        )
    }

    @Test func nothingInADockSwitchLeavesTheRowBlank() {
        let states: [(isLive: Bool, time: Double, duration: Double)] = [
            (false, 0, 0),
            (false, 0.2, 0),
            (false, 0.5, 212),
            (false, 12, 212),
            (false, 212, 212),
        ]
        for state in states {
            let face = MediaTimelineFace.face(
                isLive: state.isLive,
                currentTime: state.time,
                duration: state.duration
            )
            switch face {
            case .pending(let elapsed):
                #expect(elapsed >= 0)
            case .scrubber(_, let remaining, let progress):
                #expect(remaining >= 0)
                #expect(progress >= 0 && progress <= 1)
            case .live:
                Issue.record("a recording reported itself live")
            }
        }
    }
}

struct MediaCropMathTests {
    @Test func fullyVisiblePlayerCropsToItself() {
        let crop = MediaCropMath.visibleCrop(
            viewportRect: CGRect(x: 100, y: 50, width: 640, height: 360),
            viewBounds: CGRect(x: 0, y: 0, width: 1280, height: 800),
            topInset: 0
        )
        #expect(crop == CGRect(x: 100, y: 50, width: 640, height: 360))
    }

    @Test func topInsetShiftsThePlayerDownIntoViewCoordinates() {
        let crop = MediaCropMath.visibleCrop(
            viewportRect: CGRect(x: 100, y: 0, width: 640, height: 360),
            viewBounds: CGRect(x: 0, y: 0, width: 1280, height: 800),
            topInset: 52
        )
        #expect(crop == CGRect(x: 100, y: 52, width: 640, height: 360))
    }

    @Test func playerScrolledPartlyOutClampsToTheViewport() {
        let crop = MediaCropMath.visibleCrop(
            viewportRect: CGRect(x: 0, y: -100, width: 640, height: 360),
            viewBounds: CGRect(x: 0, y: 0, width: 1280, height: 800),
            topInset: 0
        )
        #expect(crop == CGRect(x: 0, y: 0, width: 640, height: 260))
    }

    @Test func playerScrolledAwayHasNoCrop() {
        let crop = MediaCropMath.visibleCrop(
            viewportRect: CGRect(x: 0, y: -340, width: 640, height: 360),
            viewBounds: CGRect(x: 0, y: 0, width: 1280, height: 800),
            topInset: 0
        )
        #expect(crop == nil)
    }

    @Test func cardHeightFollowsTheCropAspect() {
        let height = MediaCropMath.cardHeight(
            width: 320,
            crop: CGRect(x: 0, y: 0, width: 640, height: 360)
        )
        #expect(height == 180)
    }

    @Test func cardHeightIsClampedForVerticalVideo() {
        let height = MediaCropMath.cardHeight(
            width: 320,
            crop: CGRect(x: 0, y: 0, width: 360, height: 640)
        )
        #expect(height == 320)
    }

    @Test func scaledBoundsShowExactlyTheCropAtMatchingAspect() {
        let bounds = MediaCropMath.scaledBounds(
            cardSize: CGSize(width: 320, height: 180),
            crop: CGRect(x: 100, y: 52, width: 640, height: 360)
        )
        #expect(bounds == CGRect(x: 100, y: 52, width: 640, height: 360))
    }

    @Test func scaledBoundsCenterVerticallyWhenTheCardIsShorter() {
        let bounds = MediaCropMath.scaledBounds(
            cardSize: CGSize(width: 320, height: 160),
            crop: CGRect(x: 0, y: 0, width: 640, height: 360)
        )
        #expect(bounds == CGRect(x: 0, y: 20, width: 640, height: 320))
    }
}
