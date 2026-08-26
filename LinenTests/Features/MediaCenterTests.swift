// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
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

    @Test func aDeadContentProcessDropsThePictureAndTheClock() {
        let media = MediaCenter()
        let webView = WKWebView()

        lend(media, webView, tabID: UUID())
        media.model.playerViewportRect = CGRect(x: 0, y: 0, width: 640, height: 360)
        media.model.currentTime = 1
        media.model.duration = 120
        media.model.isLive = true
        media.model.isPlaying = true

        media.pageDidReset(webView)

        #expect(media.model.pictureWebView == nil)
        #expect(media.model.playerViewportRect == nil)
        #expect(media.model.currentTime == 0)
        #expect(media.model.duration == 0)
        #expect(media.model.isLive == false)
        #expect(media.model.isPlaying == false)
    }

    @Test func anotherTabsDeadProcessLeavesTheDockAlone() {
        let media = MediaCenter()
        let docked = WKWebView()

        lend(media, docked, tabID: UUID())
        media.model.playerViewportRect = CGRect(x: 0, y: 0, width: 640, height: 360)

        media.pageDidReset(WKWebView())

        #expect(media.model.pictureWebView === docked)
        #expect(media.model.playerViewportRect != nil)
    }

    @Test func aPageThatComesBackTakesThePictureAgain() {
        let media = MediaCenter()
        let webView = WKWebView()
        media.controlTab(webView: webView, title: "Playing", tabID: UUID(), artwork: nil)

        media.receiveScriptMessage(
            "state:{\"t\":1,\"d\":100,\"l\":0,\"p\":1,\"v\":1,\"m\":0,\"w\":1280}",
            from: webView,
            isMainFrame: true
        )
        media.receiveScriptMessage("hello", from: webView, isMainFrame: true)
        #expect(media.model.pictureWebView == nil)

        media.receiveScriptMessage(
            "state:{\"t\":3,\"d\":100,\"l\":0,\"p\":1,\"v\":1,\"m\":0,\"w\":1280}",
            from: webView,
            isMainFrame: true
        )

        #expect(media.model.pictureWebView === webView)
        #expect(media.model.currentTime == 3)
    }

    @Test func aSubframeReloadIsNotThePageComingBack() {
        let media = MediaCenter()
        let webView = WKWebView()

        lend(media, webView, tabID: UUID())
        media.model.playerViewportRect = CGRect(x: 0, y: 0, width: 640, height: 360)

        media.receiveScriptMessage("hello", from: webView, isMainFrame: false)

        #expect(media.model.pictureWebView === webView)
        #expect(media.model.playerViewportRect != nil)
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

    // MARK: - The player turned off in Settings

    @Test func theMediaPlayerIsOnUntilItIsTurnedOff() {
        let defaults = UserDefaults(suiteName: "MediaPlayerTests-\(UUID().uuidString)")!

        #expect(BrowserSettings(defaults: defaults).showsMediaPlayer)

        BrowserSettings(defaults: defaults).showsMediaPlayer = false

        #expect(!BrowserSettings(defaults: defaults).showsMediaPlayer)
    }

    // MARK: - Automatic Picture in Picture

    @Test func picturesStayInTheirTabUntilAutomaticPiPIsTurnedOn() {
        let defaults = UserDefaults(suiteName: "AutomaticPiPTests-\(UUID().uuidString)")!

        #expect(!BrowserSettings(defaults: defaults).automaticPictureInPicture)

        BrowserSettings(defaults: defaults).automaticPictureInPicture = true

        #expect(BrowserSettings(defaults: defaults).automaticPictureInPicture)
    }

    @Test func theVideoInThePlayerIsAnExperimentNobodyOptedInto() {
        let defaults = UserDefaults(suiteName: "VideoInPlayerTests-\(UUID().uuidString)")!

        #expect(!BrowserSettings(defaults: defaults).showsVideoInPlayer)

        BrowserSettings(defaults: defaults).showsVideoInPlayer = true

        #expect(BrowserSettings(defaults: defaults).showsVideoInPlayer)
    }

    @Test func theExperimentTakesAutomaticPiPWithIt() {
        let defaults = UserDefaults(suiteName: "VideoInPlayerTakesPiP-\(UUID().uuidString)")!
        let settings = BrowserSettings(defaults: defaults)
        settings.automaticPictureInPicture = true

        settings.showsVideoInPlayer = true

        #expect(!settings.automaticPictureInPicture)
        #expect(!BrowserSettings(defaults: defaults).automaticPictureInPicture)
    }

    @Test func theStripNeverBorrowsAPictureWhileTheExperimentIsOff() {
        let media = MediaCenter()
        media.lendsPicture = false
        let webView = WKWebView()
        media.controlTab(webView: webView, title: "Playing", tabID: UUID(), artwork: nil)

        media.receiveScriptMessage(
            "state:{\"t\":1,\"d\":100,\"l\":0,\"p\":1,\"v\":1,\"m\":0,\"w\":640}",
            from: webView,
            isMainFrame: true
        )

        #expect(media.model.hasVideo, "the strip still owes the user a Picture in Picture button")
        #expect(media.model.pictureWebView == nil)
    }

    @Test func turningTheVideoOffTakesTheLentPictureBack() {
        let media = MediaCenter()
        let webView = WKWebView()
        lend(media, webView, tabID: UUID())
        #expect(media.model.pictureWebView === webView)

        media.lendsPicture = false

        #expect(media.model.pictureWebView == nil)
    }

    @Test func comingBackFromPictureInPictureNamesTheViewThatReturned() {
        let media = MediaCenter()
        var returned: [WKWebView?] = []
        media.onReturnedInline = { returned.append($0) }
        let webView = WKWebView()
        media.controlTab(webView: webView, title: "Playing", tabID: UUID(), artwork: nil)

        media.receiveScriptMessage("picture-in-picture", from: webView, isMainFrame: true)
        media.receiveScriptMessage("inline", from: webView, isMainFrame: true)

        #expect(returned.count == 1)
        #expect(returned.first ?? nil === webView)
    }

    /// Leaving full screen reports `inline` too, and must not send anybody
    /// anywhere.
    @Test func leavingFullScreenIsNotComingBackFromPictureInPicture() {
        let media = MediaCenter()
        var returned = 0
        media.onReturnedInline = { _ in returned += 1 }
        let webView = WKWebView()
        media.controlTab(webView: webView, title: "Playing", tabID: UUID(), artwork: nil)

        media.receiveScriptMessage("inline", from: webView, isMainFrame: true)

        #expect(returned == 0)
    }

    @Test func aTabThatIsNotDockedAlsoReportsItsWayBack() {
        let media = MediaCenter()
        var returned: [WKWebView?] = []
        media.onReturnedInline = { returned.append($0) }
        let webView = WKWebView()
        media.requestNativePiP(on: webView)

        media.receiveScriptMessage("picture-in-picture", from: webView, isMainFrame: true)
        media.receiveScriptMessage("inline", from: webView, isMainFrame: true)

        #expect(returned.count == 1)
        #expect(returned.first ?? nil === webView)
    }

    /// Every switch to another app asks again. The ask must not make the app
    /// forget that the video is already out, or the way back is swallowed.
    @Test func askingAgainWhileItIsAlreadyOutKeepsTheWayBack() {
        let media = MediaCenter()
        var returned = 0
        media.onReturnedInline = { _ in returned += 1 }
        let webView = WKWebView()

        media.requestNativePiP(on: webView)
        media.receiveScriptMessage("picture-in-picture", from: webView, isMainFrame: true)
        media.requestNativePiP(on: webView)
        media.receiveScriptMessage("inline", from: webView, isMainFrame: true)

        #expect(returned == 1)
    }

    @Test func aFreshPageForgetsThatSomethingWasOut() {
        let media = MediaCenter()
        var returned = 0
        media.onReturnedInline = { _ in returned += 1 }
        let webView = WKWebView()

        media.requestNativePiP(on: webView)
        media.receiveScriptMessage("picture-in-picture", from: webView, isMainFrame: true)
        media.receiveScriptMessage("hello", from: webView, isMainFrame: true)
        media.receiveScriptMessage("inline", from: webView, isMainFrame: true)

        #expect(returned == 0)
    }

    /// WebKit warns about a return while the video is still on its way out, so
    /// the warning must not drag the window forward the moment PiP starts.
    @Test func theTabWithTheFloatingWindowIsNamedToTheChrome() {
        let media = MediaCenter()
        var reports: [Bool] = []
        let webView = WKWebView()
        media.onPictureOutChanged = { view, isOut in
            guard view === webView else { return }
            reports.append(isOut)
        }

        media.setPictureInPicture(true, for: webView, source: .page)
        media.setPictureInPicture(true, for: webView, source: .page)
        media.setPictureInPicture(false, for: webView, source: .page)

        #expect(reports == [true, false], "the chrome must hear each change once")
    }

    @Test func aPageThatGrowsAVideoTellsItsTab() {
        let media = MediaCenter()
        var reports: [Bool] = []
        let webView = WKWebView()
        media.onTabVideoChanged = { _, hasVideo in reports.append(hasVideo) }
        media.controlTab(webView: webView, title: "Playing", tabID: UUID(), artwork: nil)

        media.receiveScriptMessage("video:1", from: webView, isMainFrame: true)
        media.receiveScriptMessage("video:0", from: webView, isMainFrame: true)

        #expect(reports == [true, false])
    }

    /// The bug: opening the docked tab from the player's arrow sent the video
    /// *out* instead of bringing it back, because the way home was a toggle and
    /// the app still believed a picture was out that WebKit had already closed.
    @Test func askingAPictureHomeWhenItIsAlreadyHomeSendsNothingOut() {
        let media = MediaCenter()
        var reports: [Bool] = []
        let webView = WKWebView()
        media.onPictureOutChanged = { _, isOut in reports.append(isOut) }

        media.setPictureInPicture(true, for: webView, source: .page)
        media.exitPictureInPicture(for: webView)

        #expect(reports == [true, false], "the belief must be corrected, not acted on")
        #expect(!media.isPictureOut(webView))
    }

    @Test func aPageThatDiesForgetsItsPicture() {
        let media = MediaCenter()
        var reports: [Bool] = []
        let webView = WKWebView()
        media.onPictureOutChanged = { _, isOut in reports.append(isOut) }

        media.setPictureInPicture(true, for: webView, source: .page)
        media.pageDidReset(webView)

        #expect(reports == [true, false])
        #expect(!media.isPictureOut(webView))
    }

    @Test func onlyOneTabCanHoldTheFloatingWindow() {
        let media = MediaCenter()
        var reports: [(WKWebView, Bool)] = []
        let first = WKWebView()
        let second = WKWebView()
        media.onPictureOutChanged = { view, isOut in reports.append((view, isOut)) }

        media.setPictureInPicture(true, for: first, source: .page)
        media.setPictureInPicture(true, for: second, source: .page)

        #expect(!media.isPictureOut(first), "the first tab must not still claim the window")
        #expect(media.isPictureOut(second))
        #expect(reports.count == 3)
        #expect(reports[1].0 === first)
        #expect(reports[1].1 == false)
    }

    @Test func aFreshDocumentForgetsThePictureEverywhere() {
        let media = MediaCenter()
        var reports: [Bool] = []
        let webView = WKWebView()
        media.onPictureOutChanged = { _, isOut in reports.append(isOut) }

        media.setPictureInPicture(true, for: webView, source: .page)
        media.receiveScriptMessage("hello", from: webView, isMainFrame: true)

        #expect(reports == [true, false])
        #expect(!media.isPictureOut(webView))
    }

    @Test func dockingATabWhoseVideoIsOutSaysSo() {
        let media = MediaCenter()
        let webView = WKWebView()

        media.setPictureInPicture(true, for: webView, source: .page)
        media.controlTab(webView: webView, title: "Playing", tabID: UUID(), artwork: nil)

        #expect(media.model.isInNativePiP, "the player would offer to send out what is already out")
    }

    @Test func anEmptyDockDescribesNoPicture() {
        let media = MediaCenter()
        let webView = WKWebView()
        media.controlTab(webView: webView, title: "Playing", tabID: UUID(), artwork: nil)
        media.setPictureInPicture(true, for: webView, source: .page)

        media.releaseControl()

        #expect(!media.model.isInNativePiP)
    }

    /// A background tab that navigates tears its own picture down, and only
    /// WebKit reports that. It is not the user asking to be taken there.
    @Test func aPictureTornDownUnderneathTakesTheUserNowhere() {
        let media = MediaCenter()
        var returned = 0
        media.onReturnedInline = { _ in returned += 1 }
        let webView = WKWebView()

        media.setPictureInPicture(true, for: webView, source: .page)
        media.setPictureInPicture(false, for: webView, source: .webKit)

        #expect(returned == 0)
        #expect(!media.isPictureOut(webView), "the state still has to settle")
    }

    /// A living page only speaks when something in it changed, so its word is
    /// the user's word.
    @Test func aPageThatSaysTheVideoCameHomeTakesTheUserToIt() {
        let media = MediaCenter()
        var returned = 0
        media.onReturnedInline = { _ in returned += 1 }
        let webView = WKWebView()

        media.setPictureInPicture(true, for: webView, source: .page)
        media.setPictureInPicture(false, for: webView, source: .page)

        #expect(returned == 1)
    }

    @Test func whatTheAppItselfSendsHomeStillTakesTheUserToIt() {
        let media = MediaCenter()
        var returned = 0
        media.onReturnedInline = { _ in returned += 1 }
        let webView = WKWebView()

        media.setPictureInPicture(true, for: webView, source: .page)
        media.togglePictureInPicture(for: webView)
        media.setPictureInPicture(false, for: webView, source: .webKit)

        #expect(returned == 1)
    }

    @Test func aPictureOnItsWayOutIsNotAskingToComeBack() {
        let media = MediaCenter()
        let webView = WKWebView()

        media.setPictureInPicture(true, for: webView, source: .page)

        #expect(!media.notePictureReturnAsk(for: webView))
    }

    @Test func nothingThatIsNotOutIsAskingToComeBack() {
        let media = MediaCenter()

        #expect(!media.notePictureReturnAsk(for: WKWebView()))
    }

    @Test func aTabThatNeverLeftForThePictureReportsNothing() {
        let media = MediaCenter()
        var returned = 0
        media.onReturnedInline = { _ in returned += 1 }
        let webView = WKWebView()
        media.requestNativePiP(on: webView)

        media.receiveScriptMessage("inline", from: webView, isMainFrame: true)

        #expect(returned == 0)
    }

    @Test func aRectFromThePictureTargetLeavesTheDockedRectAlone() {
        let media = MediaCenter()
        let docked = WKWebView()
        let other = WKWebView()
        lend(media, docked, tabID: UUID())
        media.model.playerViewportRect = CGRect(x: 0, y: 0, width: 640, height: 360)

        media.requestNativePiP(on: other)
        media.receiveScriptMessage(
            "rect:{\"x\":8,\"y\":8,\"w\":320,\"h\":180}",
            from: other,
            isMainFrame: true
        )

        #expect(media.model.playerViewportRect == CGRect(x: 0, y: 0, width: 640, height: 360))
    }

    @Test func nothingDocksWhileThePlayerIsOff() {
        let media = MediaCenter()
        media.isEnabled = false

        media.controlTab(webView: WKWebView(), title: "Playing", tabID: UUID(), artwork: nil)

        #expect(!media.model.isActive)
        #expect(media.controlledTabID == nil)
    }

    @Test func turningThePlayerOffLetsGoOfWhatWasDocked() {
        let media = MediaCenter()
        media.controlTab(webView: WKWebView(), title: "Playing", tabID: UUID(), artwork: nil)
        #expect(media.model.isActive)

        media.isEnabled = false

        #expect(!media.model.isActive)
        #expect(media.controlledTabID == nil)
    }

    @Test func theTabYouAreLookingAtIsStillReadWithThePlayerOff() {
        let media = MediaCenter()
        media.isEnabled = false
        let page = WKWebView()

        media.watch(webView: page, title: "Adele - Easy On Me", tabID: UUID(), artwork: nil)
        media.receiveScriptMessage(
            "state:{\"t\":12,\"d\":331,\"l\":0,\"p\":1,\"v\":1,\"m\":0,\"w\":640}",
            from: page,
            isMainFrame: true
        )

        #expect(media.watched.isActive, "the lyrics still follow the tab you are on")
        #expect(media.watched.duration == 331)
    }

    @Test func lettingGoOfTheWatchedTabForgetsItsTrack() {
        let media = MediaCenter()
        let page = WKWebView()

        media.watch(webView: page, title: "YouTube", tabID: UUID(), artwork: nil)
        media.receiveScriptMessage(
            "meta:{\"t\":\"Ordinary\",\"a\":\"Alex Warren\",\"al\":\"\",\"art\":\"\",\"g\":\"0\"}",
            from: page,
            isMainFrame: true
        )
        #expect(media.watched.trackTitle == "Ordinary")

        media.stopWatching()

        #expect(media.watched.controlledTabID == nil)
        #expect(media.watched.trackTitle.isEmpty, "a header must not keep a song nothing is watching")
        #expect(media.watched.artist.isEmpty)
        #expect(media.watched.title.isEmpty)
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
        var rect: String?
        _ = await waitUntil {
            rect = collector.messages.last { $0.hasPrefix("rect:") }
            return rect != nil
        }
        return rect
    }

    private func waitForMessage(_ collector: Collector, prefix: String) async -> Bool {
        await waitUntil { collector.messages.contains { $0.hasPrefix(prefix) } }
    }

    private func settle(_ webView: WKWebView, _ collector: Collector) async {
        collector.messages.removeAll { $0.hasPrefix("rect:") }
        _ = try? await webView.evaluateJavaScript("window.postMessage('linen-resend', '*')")
        _ = await waitForMessage(collector, prefix: "rect:")
    }

    @Test func thePlayerRectIsReported() async {
        let (_, collector) = await playerWebView()

        let rect = await waitForRect(collector)

        #expect(rect?.contains("\"w\":640") == true)
        #expect(rect?.contains("\"h\":360") == true)
    }

    /// A detached player keeps its last currentTime and videoWidth.
    @Test func aDetachedPlayerIsNotStillReported() async {
        let (webView, collector) = await playerWebView()
        _ = await waitForRect(collector)

        _ = try? await webView.evaluateJavaScript("document.querySelector('video').remove()")
        collector.messages.removeAll()
        _ = try? await webView.evaluateJavaScript("window.postMessage('linen-resend', '*')")
        try? await Task.sleep(for: .milliseconds(250))

        #expect(!collector.messages.contains { $0.hasPrefix("state:") })
    }

    @Test func aLoadedPageAnnouncesItself() async {
        let (_, collector) = await playerWebView()

        for _ in 0..<100 where !collector.messages.contains("hello") {
            try? await Task.sleep(for: .milliseconds(100))
        }

        #expect(collector.messages.contains("hello"))
    }

    @Test func askingForTheRectReportsItAgainWithoutARequestToReveal() async {
        let (webView, collector) = await playerWebView()
        _ = await waitForRect(collector)
        collector.messages.removeAll()

        _ = try? await webView.evaluateJavaScript("window.postMessage('linen-rect', '*')")

        let rect = await waitForRect(collector)
        #expect(rect?.contains("\"w\":640") == true)
    }

    /// A page whose player has no frames must never be clicked for a gesture:
    /// the click would land on whatever the page has there instead.
    @Test func aPlayerWithoutFramesNeverAsksForAGesture() async {
        let (webView, collector) = await playerWebView()
        _ = await waitForRect(collector)
        collector.messages.removeAll()

        _ = try? await webView.evaluateJavaScript("window.postMessage('linen-pip', '*')")
        #expect(await waitForMessage(collector, prefix: "diag:no-video"))

        #expect(!collector.messages.contains("diag:need-gesture"))
    }

    @Test func aPausedPlayerStaysOutOfPictureInPictureOnItsOwn() async {
        let (webView, collector) = await playerWebView()
        _ = await waitForRect(collector)
        collector.messages.removeAll()

        _ = try? await webView.evaluateJavaScript("window.postMessage('linen-pip-auto', '*')")
        #expect(await waitForMessage(collector, prefix: "diag:not-playing"))

        #expect(!collector.messages.contains("diag:need-gesture"))
    }

    /// Asking for it yourself still works on a paused video; only the automatic
    /// request waits for something to be playing.
    @Test func askingForPictureInPictureIgnoresWhetherItIsPlaying() async {
        let (webView, collector) = await playerWebView()
        _ = await waitForRect(collector)
        collector.messages.removeAll()

        _ = try? await webView.evaluateJavaScript("window.postMessage('linen-pip', '*')")
        await settle(webView, collector)

        #expect(!collector.messages.contains("diag:not-playing"))
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
