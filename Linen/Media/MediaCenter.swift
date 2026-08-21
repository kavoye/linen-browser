// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import os
import SwiftUI
import WebKit

@MainActor
@Observable
final class MediaModel {
    var title = ""
    var pageTitle = ""
    var trackTitle = ""
    var artist = ""
    var album = ""
    var isActive = false
    var isInNativePiP = false
    var hasVideo = false

    // MARK: - Transport state

    var isPlaying = false
    var currentTime: Double = 0
    var duration: Double = 0
    var volume: Double = 1
    var isMuted = false
    var artworkURL: URL?
    var pictureWebView: WKWebView?

    var playerViewportRect: CGRect?
    var controlledTabID: UUID?

    var isLive = false

    var progress: Double? {
        guard !isLive, duration > 0 else { return nil }
        return min(max(currentTime / duration, 0), 1)
    }
}

/// Who says a video went out or came home. A live document only speaks when
/// something in it changed, so the page speaks for the user; WebKit also speaks
/// while tearing a page down, which nobody asked for.
enum PictureSource {
    case page
    case webKit

    var speaksForTheUser: Bool {
        self == .page
    }

    var name: String {
        self == .page ? "the page" : "WebKit"
    }
}

@MainActor
final class MediaCenter {
    let model = MediaModel()
    let watched = MediaModel()

    /// Off in Settings, nothing docks: what plays stays in its own tab. The
    /// watched model is untouched, so the lyrics still follow the tab you are on.
    var isEnabled = true {
        didSet {
            guard !isEnabled else { return }
            releaseControl()
        }
    }

    /// Video that pops out on its own belongs in the floating window, so the
    /// card keeps its artwork instead of cropping a picture nobody can see.
    var lendsPicture = true {
        didSet {
            guard !lendsPicture else { return }
            setPicture(nil)
        }
    }
    var onReturnedInline: ((WKWebView?) -> Void)?
    var onTabAudioChanged: ((WKWebView, Bool) -> Void)?
    var onTabVideoChanged: ((WKWebView, Bool) -> Void)?
    var onPictureOutChanged: ((WKWebView, Bool) -> Void)?
    var onControlledTabChanged: ((UUID?, UUID?) -> Void)?
    var onPictureChanged: (() -> Void)?

    private let messageHandler = MediaMessageHandler()

    var frameScriptHandler: any WKScriptMessageHandler & AnyObject {
        messageHandler
    }
    nonisolated static var frameScriptSource: String {
        MediaScript.source
    }
    nonisolated static let frameScriptHandlerName = "linenpip"

    init() {
        messageHandler.onMessage = { [weak self] message, webView, isMainFrame in
            self?.receiveScriptMessage(message, from: webView, isMainFrame: isMainFrame)
        }
    }

    func receiveScriptMessage(_ message: String, from webView: WKWebView?, isMainFrame: Bool) {
        if let webView, message == "picture-in-picture" || message == "inline" {
            applyPresentationMode(message, from: webView)
            return
        }
        if let webView, isMainFrame, message == "hello" {
            forgetPicture(webView)
        }
        if let controlled = controlledWebView, webView === controlled {
            if isMainFrame, let playing = Self.audioReport(in: message) {
                onTabAudioChanged?(controlled, playing)
            }
            if isMainFrame, let hasVideo = Self.videoReport(in: message) {
                onTabVideoChanged?(controlled, hasVideo)
            }
            handleScriptMessage(message, from: controlled, isMainFrame: isMainFrame)
            return
        }
        if let webView, webView === pipTarget,
           handlePiPMessage(message, from: webView, isMainFrame: isMainFrame) {
            return
        }
        guard isMainFrame else { return }
        if let playing = Self.audioReport(in: message), let webView {
            onTabAudioChanged?(webView, playing)
        }
        if let hasVideo = Self.videoReport(in: message), let webView {
            onTabVideoChanged?(webView, hasVideo)
        }
        if let watchedWebView, webView === watchedWebView {
            applyWatched(message)
        }
    }

    // MARK: - The tab you are looking at

    func watch(webView: WKWebView, title: String, tabID: UUID, artwork: URL?) {
        guard watchedWebView !== webView else { return }
        watchedWebView = webView
        watched.artworkURL = artwork
        watched.controlledTabID = tabID
        watched.pageTitle = title
        watched.trackTitle = ""
        watched.artist = ""
        watched.album = ""
        watched.title = title
        watched.currentTime = 0
        watched.duration = 0
        watched.isLive = false
        watched.isPlaying = true
        watched.isActive = true
        Self.post("linen-resend", to: webView)
    }

    func stopWatching() {
        guard watchedWebView != nil else { return }
        watchedWebView = nil
        watched.controlledTabID = nil
        watched.artworkURL = nil
        watched.title = ""
        watched.pageTitle = ""
        watched.trackTitle = ""
        watched.artist = ""
        watched.album = ""
        watched.isActive = false
    }

    private func applyWatched(_ message: String) {
        if message == "hello" {
            watched.currentTime = 0
            watched.duration = 0
            watched.isLive = false
            return
        }
        if message.hasPrefix("state:") {
            guard let fields = Self.fields(in: String(message.dropFirst("state:".count))) else { return }
            applyTiming(fields, to: watched)
            return
        }
        if message.hasPrefix("meta:") {
            applyMetadata(String(message.dropFirst("meta:".count)), to: watched)
            return
        }
        if message == "ended" {
            watched.isPlaying = false
        }
    }

    // MARK: - The tab in the dock

    func controlTab(
        webView: WKWebView,
        title: String,
        tabID: UUID,
        isPlaying: Bool = true,
        artwork: URL?
    ) {
        guard isEnabled, controlledTabID != tabID else { return }

        let previous = controlledTabID
        setPicture(nil)
        model.playerViewportRect = nil
        model.controlledTabID = tabID
        controlledWebView = webView
        onControlledTabChanged?(previous, tabID)
        model.artworkURL = artwork
        artworkIsGuess = artwork == nil
        model.pageTitle = title
        model.trackTitle = ""
        model.artist = ""
        model.album = ""
        model.title = title.isEmpty ? String(localized: "Now Playing") : title
        model.isInNativePiP = nativePiPView === webView
        model.hasVideo = false
        model.isPlaying = isPlaying
        model.isLive = false
        model.currentTime = 0
        model.duration = 0
        model.isActive = true
        needsReveal = true
        Self.post("linen-resend", to: webView)
        Pipeline.log.notice("media: controlling playback in a background tab")
    }

    func releaseControl() {
        guard let previous = controlledTabID else { return }
        setPicture(nil)
        model.isInNativePiP = false
        model.hasVideo = false
        model.playerViewportRect = nil
        model.controlledTabID = nil
        controlledWebView = nil
        onControlledTabChanged?(previous, nil)
        model.artworkURL = nil
        model.pageTitle = ""
        model.trackTitle = ""
        model.artist = ""
        model.album = ""
        model.isActive = false
        needsReveal = true
        Pipeline.log.notice("media: released tab playback control")
    }

    func pageDidReset(_ webView: WKWebView) {
        forgetPicture(webView)
        if webView === watchedWebView {
            watched.currentTime = 0
            watched.duration = 0
            watched.isLive = false
        }
        guard webView === controlledWebView else { return }
        forgetControlledPage()
    }

    private func forgetControlledPage() {
        setPicture(nil)
        model.hasVideo = false
        model.pageTitle = ""
        model.trackTitle = ""
        model.artist = ""
        model.album = ""
        model.title = String(localized: "Now Playing")
        model.artworkURL = nil
        artworkIsGuess = true
        model.playerViewportRect = nil
        model.currentTime = 0
        model.duration = 0
        model.isLive = false
        model.isPlaying = false
        needsReveal = true
    }

    private func setPicture(_ webView: WKWebView?) {
        guard model.pictureWebView !== webView else { return }
        model.pictureWebView = webView
        onPictureChanged?()
    }

    var controlledTabID: UUID? {
        model.controlledTabID
    }
    private weak var controlledWebView: WKWebView?
    private weak var watchedWebView: WKWebView?
    private var needsReveal = true

    var pictureCrop: CGRect? {
        guard let webView = model.pictureWebView,
              let rect = model.playerViewportRect else { return nil }
        return MediaCropMath.visibleCrop(
            viewportRect: rect,
            viewBounds: webView.bounds,
            topInset: webView.obscuredContentInsets.top
        )
    }
    private var artworkIsGuess = true

    nonisolated static func poster(forPage urlString: String) -> URL? {
        guard let url = URL(string: urlString), let host = url.host()?.lowercased() else { return nil }
        let path = url.pathComponents.dropFirst()

        if host.contains("twitch.tv") {
            guard path.count == 1, let login = path.first,
                  !login.isEmpty,
                  login.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") })
            else { return nil }
            return URL(string: "https://static-cdn.jtvnw.net/previews-ttv/live_user_\(login.lowercased())-440x248.jpg")
        }

        var id: String?
        if host.contains("youtube.com") {
            id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "v" }?.value
        } else if host.contains("youtu.be") {
            id = path.first
        }
        guard let id, !id.isEmpty else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg")
    }

    func close() {
        guard model.isActive else { return }
        send("linen-pause")
        releaseControl()
    }

    // MARK: - Transport

    func playPause() {
        model.isPlaying.toggle()
        send(model.isPlaying ? "linen-play" : "linen-pause")
    }

    func skip(by seconds: Double) {
        if model.duration > 0 {
            model.currentTime = min(max(model.currentTime + seconds, 0), model.duration)
        }
        send("linen-seek:\(seconds)")
    }

    func seek(toFraction fraction: Double) {
        let clamped = min(max(fraction, 0), 1)
        if model.duration > 0 {
            model.currentTime = model.duration * clamped
        }
        send("linen-seekto:\(clamped)")
    }

    func setVolume(_ volume: Double) {
        let clamped = min(max(volume, 0), 1)
        model.volume = clamped
        model.isMuted = clamped <= 0
        send("linen-volume:\(clamped)")
    }

    func toggleMute() {
        model.isMuted.toggle()
        send("linen-mute:\(model.isMuted ? 1 : 0)")
    }

    private func send(_ message: String) {
        guard let controlledWebView else { return }
        Self.post(message, to: controlledWebView)
    }

    static func seek(to seconds: Double, on webView: WKWebView) {
        post("linen-seekabs:\(seconds)", to: webView)
    }

    static func setMuted(_ muted: Bool, on webView: WKWebView) {
        post("linen-mute:\(muted ? 1 : 0)", to: webView)
    }

    private static func post(_ message: String, to webView: WKWebView) {
        webView.evaluateJavaScript("""
        window.postMessage('\(message)', '*');
        Array.prototype.forEach.call(document.querySelectorAll('iframe'), function (f) {
          try { f.contentWindow.postMessage('\(message)', '*'); } catch (e) {}
        });
        """)
    }

    nonisolated private static func audioReport(in message: String) -> Bool? {
        guard message.hasPrefix("audio:") else { return nil }
        return message.hasSuffix("1")
    }

    nonisolated private static func videoReport(in message: String) -> Bool? {
        guard message.hasPrefix("video:") else { return nil }
        return message.hasSuffix("1")
    }

    func toggleNativePiP() {
        guard let controlledWebView else { return }
        togglePictureInPicture(for: controlledWebView)
    }

    func isPictureOut(_ webView: WKWebView) -> Bool {
        nativePiPView === webView
    }

    /// Never a toggle: a stale belief that the video is out would otherwise send
    /// it out at the very moment the user came back to watch it. Asking the page
    /// for `inline` has no other direction to go, so it is always safe to ask,
    /// and it covers a `_isPictureInPictureActive` that answers for a view it
    /// cannot see.
    func exitPictureInPicture(for webView: WKWebView) {
        guard nativePiPView === webView else { return }
        returnAskedAt = Date()
        if Self.pictureInPictureActive(webView) == true, Self.togglePictureInPicture(on: webView) {
            forgetGestureRequest()
            return
        }
        Self.post("linen-pip-exit", to: webView)
        guard Self.pictureInPictureActive(webView) == false else { return }
        Pipeline.log.notice("media: WebKit says the picture was already home")
        setPictureInPicture(false, for: webView, source: .webKit)
    }

    /// WebKit answers for a view it can see. A tab parked off screen is not one,
    /// so the synthesized gesture stays as the way in for those.
    func togglePictureInPicture(for webView: WKWebView) {
        guard nativePiPView !== webView else {
            exitPictureInPicture(for: webView)
            return
        }
        if Self.canTogglePictureInPicture(webView), Self.togglePictureInPicture(on: webView) {
            forgetGestureRequest()
            return
        }
        pipRequestedAt = Date()
        pipTarget = webView
        pipTargetRect = nil
        Self.post("linen-rect", to: webView)
        Self.post("linen-pip", to: webView)
    }

    func requestNativePiP(on webView: WKWebView) {
        guard nativePiPView !== webView else { return }
        if Self.canTogglePictureInPicture(webView), Self.togglePictureInPicture(on: webView) {
            forgetGestureRequest()
            return
        }
        pipRequestedAt = Date()
        pipTarget = webView
        pipTargetRect = nil
        Self.post("linen-rect", to: webView)
        Self.post("linen-pip-auto", to: webView)
    }

    private var pipRequestedAt: Date?
    private weak var pipTarget: WKWebView?
    private var pipTargetRect: CGRect?
    private weak var nativePiPView: WKWebView?
    private var pictureWentOutAt: Date?
    private var returnAskedAt: Date?
    private static let gestureWindow: TimeInterval = 10
    private static let settleAfterLeaving: TimeInterval = 1
    private static let returnWindow: TimeInterval = 5

    private func forgetGestureRequest() {
        pipRequestedAt = nil
        pipTarget = nil
        pipTargetRect = nil
    }

    private func forgetPicture(_ webView: WKWebView) {
        guard nativePiPView === webView else { return }
        nativePiPView = nil
        if pipTarget === webView {
            pipTarget = nil
            pipTargetRect = nil
        }
        if webView === controlledWebView {
            model.isInNativePiP = false
        }
        onPictureOutChanged?(webView, false)
    }

    /// Answers whether this is the user asking for the video back, and records
    /// the ask, so the completion that follows is known to be their doing.
    /// WebKit warns on the way *out* too, so an ask that arrives while the video
    /// is still settling into the floating window is not one.
    func notePictureReturnAsk(for webView: WKWebView) -> Bool {
        guard nativePiPView === webView else { return false }
        if let wentOut = pictureWentOutAt,
           Date().timeIntervalSince(wentOut) < Self.settleAfterLeaving {
            return false
        }
        returnAskedAt = Date()
        return true
    }

    private func returnWasAsked(for webView: WKWebView) -> Bool {
        guard let asked = returnAskedAt else { return false }
        return Date().timeIntervalSince(asked) < Self.returnWindow
    }

    private func applyPresentationMode(_ message: String, from webView: WKWebView) {
        setPictureInPicture(message == "picture-in-picture", for: webView, source: .page)
    }

    /// One truth for "which view is out in the floating window", so a docked
    /// video that gets undocked, or a second ask on the way out of the app,
    /// cannot lose the way back. WebKit answers here through the tab's UI
    /// delegate, and the injected script through its presentation-mode message.
    func setPictureInPicture(_ isNative: Bool, for webView: WKWebView, source: PictureSource) {
        if webView === controlledWebView {
            model.isInNativePiP = isNative
        }
        if isNative {
            guard nativePiPView !== webView else { return }
            if let previous = nativePiPView {
                forgetPicture(previous)
            }
            pipRequestedAt = nil
            nativePiPView = webView
            pictureWentOutAt = Date()
            onPictureOutChanged?(webView, true)
            Pipeline.log.notice("media: the picture is out, \(source.name, privacy: .public) said so")
            return
        }
        guard nativePiPView === webView else { return }
        let wasAsked = source.speaksForTheUser || returnWasAsked(for: webView)
        forgetPicture(webView)
        returnAskedAt = nil
        Pipeline.log.notice("""
        media: the picture came home, \(source.name, privacy: .public) said so, \
        asked for \(wasAsked)
        """)
        guard wasAsked else { return }
        onReturnedInline?(webView)
    }

    private func handlePiPMessage(
        _ message: String,
        from webView: WKWebView,
        isMainFrame: Bool
    ) -> Bool {
        if isMainFrame, message.hasPrefix("rect:") {
            pipTargetRect = Self.rect(in: String(message.dropFirst("rect:".count)))
            return false
        }
        if message == "diag:need-gesture" {
            answerGestureRequest(on: webView)
            return true
        }
        if message.hasPrefix("diag:") {
            Pipeline.log.notice("media \(message, privacy: .public)")
            return true
        }
        return false
    }

    private func answerGestureRequest(on webView: WKWebView) {
        guard let asked = pipRequestedAt, Date().timeIntervalSince(asked) < Self.gestureWindow else {
            Pipeline.log.notice("media: unsolicited gesture request ignored")
            return
        }
        let rect = webView === controlledWebView ? model.playerViewportRect : pipTargetRect
        synthesizeGestureClick(on: webView, viewportRect: rect)
    }

    // MARK: - Script messages

    private func handleScriptMessage(_ message: String, from source: WKWebView?, isMainFrame: Bool) {
        if message == "hello" {
            if isMainFrame {
                forgetControlledPage()
            }
            return
        }
        if message.hasPrefix("state:") {
            applyState(String(message.dropFirst("state:".count)), from: source)
            return
        }
        if message.hasPrefix("rect:") {
            guard isMainFrame else { return }
            applyRect(String(message.dropFirst("rect:".count)))
            return
        }
        if message == "ended" {
            model.isPlaying = false
            return
        }
        if message == "diag:need-gesture" {
            if let source {
                answerGestureRequest(on: source)
            }
            return
        }
        if message.hasPrefix("audio:") || message.hasPrefix("video:") {
            return
        }
        if message.hasPrefix("meta:") {
            applyMetadata(String(message.dropFirst("meta:".count)), to: model)
            return
        }
        if message.hasPrefix("diag:") {
            Pipeline.log.notice("media \(message, privacy: .public)")
            return
        }
        Pipeline.log.notice("media mode → \(message, privacy: .public)")
    }

    private func applyState(_ json: String, from source: WKWebView?) {
        guard let fields = Self.fields(in: json) else { return }

        if let source, source === controlledWebView {
            let hasVideo = (fields["w"] ?? 0) > 0
            model.hasVideo = hasVideo
            if hasVideo, lendsPicture {
                setPicture(source)
                if needsReveal {
                    needsReveal = false
                    Self.post("linen-reveal", to: source)
                }
            }
        }
        applyTiming(fields, to: model)
    }

    nonisolated private static func fields(in json: String) -> [String: Double]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Double]
    }

    private func applyTiming(_ fields: [String: Double], to target: MediaModel) {
        let isLive = fields["l"] == 1
        if let time = fields["t"], abs(time - target.currentTime) > 0.05 {
            target.currentTime = time
        }
        if let duration = fields["d"], duration > 0, duration != target.duration {
            target.duration = duration
        }
        if isLive {
            if !target.isLive {
                target.isLive = true
            }
        } else if target.isLive, let duration = fields["d"], duration > 0 {
            target.isLive = false
        }
        if let playing = fields["p"] {
            let isPlaying = playing == 1
            if isPlaying != target.isPlaying {
                target.isPlaying = isPlaying
            }
        }
        if let volume = fields["v"], abs(volume - target.volume) > 0.005 {
            target.volume = volume
        }
        if let muted = fields["m"] {
            let isMuted = muted == 1
            if isMuted != target.isMuted {
                target.isMuted = isMuted
            }
        }
    }

    private func applyRect(_ json: String) {
        guard !json.isEmpty else {
            if model.playerViewportRect != nil {
                model.playerViewportRect = nil
            }
            return
        }
        guard let rect = Self.rect(in: json), rect != model.playerViewportRect else { return }
        model.playerViewportRect = rect
    }

    nonisolated private static func rect(in json: String) -> CGRect? {
        guard let data = json.data(using: .utf8),
              let fields = try? JSONSerialization.jsonObject(with: data) as? [String: Double],
              let x = fields["x"], let y = fields["y"],
              let width = fields["w"], let height = fields["h"],
              width > 0, height > 0
        else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func applyMetadata(_ json: String, to target: MediaModel) {
        guard let data = json.data(using: .utf8),
              let fields = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return }

        let track = fields["t"] ?? ""
        let artist = fields["a"] ?? ""
        let album = fields["al"] ?? ""
        if target.trackTitle != track {
            target.trackTitle = track
        }
        if target.artist != artist {
            target.artist = artist
        }
        if target.album != album {
            target.album = album
        }
        if !track.isEmpty {
            target.title = artist.isEmpty ? track : "\(track) — \(artist)"
        }

        guard let art = fields["art"], let url = URL(string: art),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http"
        else { return }
        let isGuess = fields["g"] == "1"
        if target === model {
            guard !isGuess || artworkIsGuess || model.artworkURL == nil else { return }
            artworkIsGuess = isGuess
        }
        if url != target.artworkURL {
            target.artworkURL = url
        }
    }

    private func synthesizeGestureClick(on webView: WKWebView, viewportRect: CGRect?) {
        guard let window = webView.window else {
            Pipeline.log.notice("media: no hosting window for gesture click")
            return
        }
        let point: NSPoint
        if let rect = viewportRect,
           let crop = MediaCropMath.visibleCrop(
               viewportRect: rect,
               viewBounds: webView.bounds,
               topInset: webView.obscuredContentInsets.top
           ) {
            point = NSPoint(x: crop.midX, y: crop.midY)
        } else {
            point = NSPoint(x: webView.bounds.midX, y: webView.bounds.midY)
        }
        let windowPoint = webView.convert(point, to: nil)
        func mouseEvent(_ type: NSEvent.EventType) -> NSEvent? {
            NSEvent.mouseEvent(
                with: type,
                location: windowPoint,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        }
        if let down = mouseEvent(.leftMouseDown) {
            webView.mouseDown(with: down)
        }
        if let up = mouseEvent(.leftMouseUp) {
            webView.mouseUp(with: up)
        }
    }

    // MARK: - WebKit switches (all diagnosed via the diag log)

    nonisolated private static let canToggleSelector = Selector(("_canTogglePictureInPicture"))
    nonisolated private static let toggleSelector = Selector(("_togglePictureInPicture"))
    nonisolated private static let isActiveSelector = Selector(("_isPictureInPictureActive"))

    nonisolated static func canTogglePictureInPicture(_ webView: WKWebView) -> Bool {
        answersTrue(canToggleSelector, on: webView)
    }

    nonisolated static func pictureInPictureActive(_ webView: WKWebView) -> Bool? {
        guard webView.responds(to: isActiveSelector) else { return nil }
        return answersTrue(isActiveSelector, on: webView)
    }

    @discardableResult
    nonisolated static func togglePictureInPicture(on webView: WKWebView) -> Bool {
        guard webView.responds(to: toggleSelector) else {
            Pipeline.log.notice("media: no toggle SPI, falling back to a synthesized gesture")
            return false
        }
        webView.perform(toggleSelector)
        return true
    }

    nonisolated private static func answersTrue(_ selector: Selector, on webView: WKWebView) -> Bool {
        guard webView.responds(to: selector), let method = webView.method(for: selector) else {
            return false
        }
        typealias Answer = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(method, to: Answer.self)(webView, selector)
    }

    static func enablePictureInPicture(on preferences: WKPreferences) {
        if preferences.responds(to: Selector(("_setAllowsPictureInPictureMediaPlayback:"))) {
            preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")
        }
        enablePiPFeatureFlags(on: preferences)
    }

    private static func enablePiPFeatureFlags(on preferences: WKPreferences) {
        let featuresSelector = Selector(("_features"))
        let setSelector = Selector(("_setEnabled:forFeature:"))
        guard (WKPreferences.self as AnyObject).responds(to: featuresSelector),
              preferences.responds(to: setSelector),
              let result = (WKPreferences.self as AnyObject).perform(featuresSelector),
              let features = result.takeUnretainedValue() as? [AnyObject],
              let method = preferences.method(for: setSelector)
        else {
            Pipeline.log.notice("media: feature-flag SPI unavailable, native PiP off")
            return
        }

        typealias SetEnabled = @convention(c) (AnyObject, Selector, Bool, AnyObject) -> Void
        let setEnabled = unsafeBitCast(method, to: SetEnabled.self)

        for feature in features {
            let key = (feature.value(forKey: "key") as? String) ?? ""
            let lowered = key.lowercased()
            guard lowered.contains("pictureinpicture") || lowered.contains("presentationmode") else {
                continue
            }
            setEnabled(preferences, setSelector, true, feature)
        }
    }
}

enum MediaRoster {
    static func isCandidate(
        isPlayingAudio: Bool,
        isMuted: Bool,
        isInternalPage: Bool,
        isActive: Bool,
        isVisibleInSplit: Bool,
        isDocked: Bool
    ) -> Bool {
        guard !isInternalPage, !isActive, !isVisibleInSplit else { return false }
        if isDocked {
            return true
        }
        return isPlayingAudio && !isMuted
    }

    static func isPickerItem(
        isPlayingAudio: Bool,
        isMuted: Bool,
        isInternalPage: Bool,
        isActive: Bool,
        isVisibleInSplit: Bool,
        isDocked: Bool,
        hasPlayed: Bool
    ) -> Bool {
        isCandidate(
            isPlayingAudio: isPlayingAudio || hasPlayed,
            isMuted: isMuted,
            isInternalPage: isInternalPage,
            isActive: isActive,
            isVisibleInSplit: isVisibleInSplit,
            isDocked: isDocked
        )
    }

    /// Pausing or muting must not take the words off the screen, so a tab that
    /// played its current page stays the one the lyrics follow.
    static func isLyricsSource(
        isPlayingAudio: Bool,
        hasPlayed: Bool,
        isInternalPage: Bool,
        isDeferred: Bool
    ) -> Bool {
        guard !isInternalPage, !isDeferred else { return false }
        return isPlayingAudio || hasPlayed
    }

    /// The tab you are looking at owns the words. The dock is only the fallback,
    /// so a docked stream cannot take the panel off the song in front of you.
    static func lyricsOwner(
        pinned: UUID?,
        active: UUID?,
        docked: UUID?,
        candidates: [UUID]
    ) -> UUID? {
        for choice in [pinned, active, docked] {
            if let choice, candidates.contains(choice) {
                return choice
            }
        }
        return nil
    }

    /// Leaving the window takes the video with you: the tab in front goes
    /// first, the dock answers for it, and a paused video stays where it is.
    static func pictureTarget(
        active: UUID?,
        isActivePlaying: Bool,
        docked: UUID?,
        isDockedPlaying: Bool
    ) -> UUID? {
        if let active, isActivePlaying {
            return active
        }
        return isDockedPlaying ? docked : nil
    }

    static func successor(to previous: UUID, in roster: [UUID]) -> UUID? {
        guard let index = roster.firstIndex(of: previous) else { return roster.first }
        guard roster.count > 1 else { return nil }
        return roster[(index + 1) % roster.count]
    }
}

private final class MediaMessageHandler: NSObject, WKScriptMessageHandler {
    var onMessage: ((String, WKWebView?, Bool) -> Void)?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        onMessage?(
            message.body as? String ?? "",
            message.webView,
            message.frameInfo.isMainFrame
        )
    }
}
