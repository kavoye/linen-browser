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
    var isActive = false
    var isInNativePiP = false

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

@MainActor
final class MediaCenter {
    let model = MediaModel()
    var onReturnedInline: (() -> Void)?
    var onTabAudioChanged: ((WKWebView, Bool) -> Void)?
    var onControlledTabChanged: ((UUID?, UUID?) -> Void)?
    var onPictureChanged: (() -> Void)?

    private let messageHandler = MediaMessageHandler()

    var frameScriptHandler: any WKScriptMessageHandler & AnyObject {
        messageHandler
    }
    nonisolated static var frameScriptSource: String {
        mediaScript
    }
    nonisolated static let frameScriptHandlerName = "linenpip"

    init() {
        messageHandler.onMessage = { [weak self] message, webView, isMainFrame in
            self?.receiveScriptMessage(message, from: webView, isMainFrame: isMainFrame)
        }
    }

    func receiveScriptMessage(_ message: String, from webView: WKWebView?, isMainFrame: Bool) {
        if let controlled = controlledWebView, webView === controlled {
            if isMainFrame, let playing = Self.audioReport(in: message) {
                onTabAudioChanged?(controlled, playing)
            }
            handleScriptMessage(message, from: controlled, isMainFrame: isMainFrame)
            return
        }
        guard isMainFrame else { return }
        if let playing = Self.audioReport(in: message), let webView {
            onTabAudioChanged?(webView, playing)
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
        guard controlledTabID != tabID else { return }

        let previous = controlledTabID
        setPicture(nil)
        model.playerViewportRect = nil
        model.controlledTabID = tabID
        controlledWebView = webView
        onControlledTabChanged?(previous, tabID)
        model.artworkURL = artwork
        artworkIsGuess = artwork == nil
        model.title = title.isEmpty ? String(localized: "Now Playing") : title
        model.isInNativePiP = false
        model.isPlaying = isPlaying
        model.isLive = false
        model.currentTime = 0
        model.duration = 0
        model.isActive = true
        Pipeline.log.notice("media: controlling playback in a background tab")
    }

    func releaseControl() {
        guard let previous = controlledTabID else { return }
        setPicture(nil)
        model.playerViewportRect = nil
        model.controlledTabID = nil
        controlledWebView = nil
        onControlledTabChanged?(previous, nil)
        model.artworkURL = nil
        model.isActive = false
        Pipeline.log.notice("media: released tab playback control")
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

    func toggleNativePiP() {
        let entering = !model.isInNativePiP
        pipRequestedAt = entering ? Date() : nil
        send(entering ? "linen-pip" : "linen-pip-exit")
    }

    private var pipRequestedAt: Date?
    private static let gestureWindow: TimeInterval = 10

    // MARK: - Script messages

    private func handleScriptMessage(_ message: String, from source: WKWebView?, isMainFrame: Bool) {
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
            guard let asked = pipRequestedAt, Date().timeIntervalSince(asked) < Self.gestureWindow else {
                Pipeline.log.notice("media: unsolicited gesture request ignored")
                return
            }
            synthesizeGestureClick()
            return
        }
        if message.hasPrefix("audio:") {
            return
        }
        if message.hasPrefix("meta:") {
            applyMetadata(String(message.dropFirst("meta:".count)))
            return
        }
        if message.hasPrefix("diag:") {
            Pipeline.log.notice("media \(message, privacy: .public)")
            return
        }
        Pipeline.log.notice("media mode → \(message, privacy: .public)")
        switch message {
        case "picture-in-picture":
            model.isInNativePiP = true
        case "inline":
            let wasNative = model.isInNativePiP
            model.isInNativePiP = false
            if wasNative {
                onReturnedInline?()
            }
        default:
            break
        }
    }

    private func applyState(_ json: String, from source: WKWebView?) {
        guard let data = json.data(using: .utf8),
              let fields = try? JSONSerialization.jsonObject(with: data) as? [String: Double]
        else { return }

        if model.pictureWebView == nil,
           let source, source === controlledWebView, (fields["w"] ?? 0) > 0 {
            setPicture(source)
            Self.post("linen-reveal", to: source)
        }

        let isLive = fields["l"] == 1
        if let time = fields["t"], abs(time - model.currentTime) > 0.05 {
            model.currentTime = time
        }
        if let duration = fields["d"], duration > 0, duration != model.duration {
            model.duration = duration
        }
        if isLive {
            if !model.isLive {
                model.isLive = true
            }
        } else if model.isLive, let duration = fields["d"], duration > 0 {
            model.isLive = false
        }
        if let playing = fields["p"] {
            let isPlaying = playing == 1
            if isPlaying != model.isPlaying {
                model.isPlaying = isPlaying
            }
        }
        if let volume = fields["v"], abs(volume - model.volume) > 0.005 {
            model.volume = volume
        }
        if let muted = fields["m"] {
            let isMuted = muted == 1
            if isMuted != model.isMuted {
                model.isMuted = isMuted
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
        guard let data = json.data(using: .utf8),
              let fields = try? JSONSerialization.jsonObject(with: data) as? [String: Double],
              let x = fields["x"], let y = fields["y"],
              let width = fields["w"], let height = fields["h"],
              width > 0, height > 0
        else { return }
        let rect = CGRect(x: x, y: y, width: width, height: height)
        if rect != model.playerViewportRect {
            model.playerViewportRect = rect
        }
    }

    private func applyMetadata(_ json: String) {
        guard let data = json.data(using: .utf8),
              let fields = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return }

        if let title = fields["t"], !title.isEmpty {
            if let artist = fields["a"], !artist.isEmpty {
                model.title = "\(title) — \(artist)"
            } else {
                model.title = title
            }
        }
        guard let art = fields["art"], let url = URL(string: art),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http"
        else { return }
        let isGuess = fields["g"] == "1"
        guard !isGuess || artworkIsGuess || model.artworkURL == nil else { return }
        artworkIsGuess = isGuess
        if url != model.artworkURL {
            model.artworkURL = url
        }
    }

    private func synthesizeGestureClick() {
        guard let webView = controlledWebView, let window = webView.window else {
            Pipeline.log.notice("media: no hosting window for gesture click")
            return
        }
        let point: NSPoint
        if let rect = model.playerViewportRect,
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

    nonisolated private static let mediaScript = """
    (function () {
      if (window.__linenMedia) { return; }
      window.__linenMedia = true;
      const post = function (message) {
        try { window.webkit.messageHandlers.linenpip.postMessage(message); } catch (e) {}
      };
      let video = null;
      let gestureAttempts = 0;
      let muteAll = false;
      const attached = new WeakSet();
      function media() {
        return Array.prototype.slice.call(document.querySelectorAll('video, audio'));
      }
      function primary() { return video || media()[0] || null; }
      function audible(m) {
        if (m.paused || m.ended) { return false; }
        if (muteAll) { return true; }
        if (m.muted || m.volume <= 0) { return false; }
        var tracks = m.audioTracks;
        if (tracks && m.readyState >= 2 && tracks.length === 0) { return false; }
        return true;
      }
      function anyPlaying() {
        return media().some(audible);
      }
      let lastAudio = null;
      function reportAudio() {
        const playing = anyPlaying();
        if (playing === lastAudio) { return; }
        lastAudio = playing;
        post('audio:' + (playing ? 1 : 0));
      }
      let lastMeta = '';
      function posterImage() {
        if (window !== window.top) { return ''; }
        var m = primary();
        var found = (m && m.poster) || '';
        if (!found) {
          var sources = ['meta[property="og:image"]', 'meta[name="twitter:image"]', 'link[rel="image_src"]'];
          for (var i = 0; i < sources.length && !found; i += 1) {
            var node = document.querySelector(sources[i]);
            if (node) { found = node.content || node.href || ''; }
          }
        }
        if (!found) { return ''; }
        try { return new URL(found, location.href).href; } catch (e) { return ''; }
      }
      function sendMeta() {
        try {
          var m = navigator.mediaSession ? navigator.mediaSession.metadata : null;
          var art = '';
          if (m && m.artwork && m.artwork.length) {
            art = m.artwork[m.artwork.length - 1].src || '';
          }
          var guessed = !art;
          if (guessed) { art = posterImage(); }
          if (!m && !art) { return; }
          var payload = JSON.stringify({
            t: (m && m.title) || '',
            a: (m && m.artist) || '',
            art: art,
            g: guessed ? '1' : '0'
          });
          if (payload === lastMeta) { return; }
          lastMeta = payload;
          post('meta:' + payload);
        } catch (e) {}
      }
      function stageElement() {
        const media = primary();
        if (media) { return media; }
        let best = null;
        let bestArea = 40000;
        Array.prototype.forEach.call(document.querySelectorAll('iframe'), function (frame) {
          const box = frame.getBoundingClientRect();
          const area = box.width * box.height;
          if (area > bestArea) { bestArea = area; best = frame; }
        });
        return best;
      }
      let lastRect = '';
      function reportRect() {
        if (window !== window.top) { return; }
        const stage = stageElement();
        let payload = '';
        if (stage) {
          const box = stage.getBoundingClientRect();
          if (box.width > 0 && box.height > 0) {
            payload = JSON.stringify({
              x: Math.round(box.left),
              y: Math.round(box.top),
              w: Math.round(box.width),
              h: Math.round(box.height)
            });
          }
        }
        if (payload === lastRect) { return; }
        lastRect = payload;
        post('rect:' + payload);
      }
      function forgetReportedRect() { lastRect = ''; }
      function revealStage() {
        forgetReportedRect();
        if (window !== window.top) { return; }
        const stage = stageElement();
        if (!stage) { return; }
        const box = stage.getBoundingClientRect();
        const outside = box.top < 0 || box.left < 0 ||
          box.bottom > window.innerHeight || box.right > window.innerWidth;
        if (outside) {
          try { stage.scrollIntoView({ block: 'nearest', inline: 'nearest' }); } catch (e) {}
        }
        reportRect();
      }
      const MAX_REAL_DURATION = 1e7;
      function realDuration(m) {
        const raw = m.duration;
        return (isFinite(raw) && raw > 0 && raw < MAX_REAL_DURATION) ? raw : 0;
      }
      function isLive(m) {
        const raw = m.duration;
        return !isNaN(raw) && raw !== 0 && realDuration(m) === 0;
      }
      function sendState() {
        const video = primary();
        if (!video) { return; }
        post('state:' + JSON.stringify({
          t: video.currentTime || 0,
          d: realDuration(video),
          l: isLive(video) ? 1 : 0,
          p: video.paused ? 0 : 1,
          v: video.volume,
          m: video.muted ? 1 : 0,
          w: video.videoWidth || 0
        }));
      }
      function clamp(value, low, high) { return Math.max(low, Math.min(high, value)); }
      function command(data) {
        const arg = parseFloat(data.slice(data.indexOf(':') + 1));
        if (data === 'linen-reveal') {
          revealStage();
          return;
        }
        const video = primary();
        if (!video) { return; }
        const duration = realDuration(video);
        if (data === 'linen-play') { const p = video.play(); if (p) { p.catch(function () {}); } }
        else if (data === 'linen-pause') { video.pause(); }
        else if (data.indexOf('linen-seek:') === 0) {
          video.currentTime = clamp(video.currentTime + arg, 0, duration || video.currentTime + arg);
        } else if (data.indexOf('linen-seekto:') === 0) {
          if (duration) { video.currentTime = clamp(duration * arg, 0, duration); }
        } else if (data.indexOf('linen-seekabs:') === 0) {
          video.currentTime = clamp(arg, 0, duration || arg);
        } else if (data.indexOf('linen-volume:') === 0) {
          video.muted = arg <= 0;
          video.volume = clamp(arg, 0, 1);
        } else if (data.indexOf('linen-mute:') === 0) {
          muteAll = arg === 1;
          media().forEach(function (m) { m.muted = muteAll; });
        }
        sendState();
      }
      let armedGesture = null;
      let armedGestureExpiry = null;
      function disarmGesture() {
        if (armedGesture) {
          document.removeEventListener('click', armedGesture, true);
          armedGesture = null;
        }
        if (armedGestureExpiry) {
          clearTimeout(armedGestureExpiry);
          armedGestureExpiry = null;
        }
      }
      function armGesture() {
        if (!video || video.webkitPresentationMode === 'picture-in-picture') { return; }
        if (gestureAttempts >= 4) { post('diag:gave-up'); gestureAttempts = 0; return; }
        gestureAttempts += 1;
        disarmGesture();
        armedGesture = function () {
          disarmGesture();
          const wasPlaying = !video.paused;
          try {
            video.webkitSetPresentationMode('picture-in-picture');
          } catch (err) {
            post('diag:error ' + err.message);
          }
          setTimeout(function () {
            if (wasPlaying && video && video.paused) {
              const p = video.play();
              if (p) { p.catch(function () {}); }
            }
            if (video && video.webkitPresentationMode !== 'picture-in-picture') { armGesture(); }
            else { gestureAttempts = 0; }
          }, 700);
        };
        document.addEventListener('click', armedGesture, true);
        armedGestureExpiry = setTimeout(function () {
          disarmGesture();
          gestureAttempts = 0;
          post('diag:gesture-expired');
        }, 10000);
        post('diag:need-gesture');
      }
      window.addEventListener('message', function (event) {
        if (event.source !== window && event.source !== window.parent) { return; }
        const data = event.data;
        if (typeof data !== 'string' || data.indexOf('linen-') !== 0) { return; }
        if (data === 'linen-pip') { gestureAttempts = 0; armGesture(); return; }
        if (data === 'linen-pip-exit') {
          disarmGesture();
          gestureAttempts = 0;
          if (video) { try { video.webkitSetPresentationMode('inline'); } catch (e) {} }
          return;
        }
        command(data);
      });
      function bind(found, asPrimary) {
        if (!found) { return; }
        if (asPrimary) { video = found; }
        if (!found.__linenBound) {
          found.__linenBound = true;
          if (muteAll) { found.muted = true; }
          ['play', 'pause', 'timeupdate', 'volumechange', 'durationchange', 'seeked', 'ended']
            .forEach(function (name) { found.addEventListener(name, sendState); });
          ['play', 'pause', 'ended', 'emptied', 'volumechange']
            .forEach(function (name) { found.addEventListener(name, reportAudio); });
          found.addEventListener('ended', function () { post('ended'); });
          found.addEventListener('webkitpresentationmodechanged', function () {
            post(found.webkitPresentationMode);
          });
        }
        sendState();
        reportAudio();
      }
      function scan() {
        const main = document.querySelector('video');
        if (main && main !== video) { bind(main, true); }
        media().forEach(function (m) { if (!m.__linenBound) { bind(m, false); } });
        sendMeta();
        reportAudio();
        reportRect();
      }
      scan();
      setInterval(scan, 500);
    })();
    """
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
