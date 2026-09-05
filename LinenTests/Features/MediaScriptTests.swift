// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
/// What the injected script decides on its own, against the real player it
/// reads. The Swift side is fed `state:` lines by `MediaCenterTests`; nothing
/// there says which numbers the page puts in them.
@Suite(.serialized, .boundedWebViews)
struct MediaScriptTests {
    private final class Collector: NSObject, WKScriptMessageHandler {
        var messages: [String] = []

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            messages.append(message.body as? String ?? "")
        }
    }

    /// A `<video>` with no source answers every read with a browser default and
    /// refuses most writes, so the fields the script reads are replaced with
    /// plain storage the test can set.
    private static let stand = """
    (() => {
      const video = document.querySelector('video');
      const box = {
        duration: NaN,
        currentTime: 0,
        paused: true,
        ended: false,
        muted: false,
        volume: 1,
        readyState: 0,
        audioTracks: null,
        videoWidth: 0
      };
      window.__box = box;
      for (const key of Object.keys(box)) {
        Object.defineProperty(video, key, {
          configurable: true,
          get() { return box[key]; },
          set(value) { box[key] = value; }
        });
      }
      Object.defineProperty(navigator, 'userActivation', {
        configurable: true,
        get() { return { hasBeenActive: false, isActive: false }; }
      });
      return true;
    })()
    """

    private func player() async -> (WKWebView, Collector) {
        let collector = Collector()
        let configuration = WebViewPool.makeConfiguration()
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
        #expect(await waitUntil { collector.messages.contains("hello") })
        _ = try? await webView.evaluateJavaScript(Self.stand)
        return (webView, collector)
    }

    /// Runs `script`, asks the page to report, and reads the line it sends.
    @discardableResult
    private func state(
        _ webView: WKWebView,
        _ collector: Collector,
        after script: String = "",
        resending: Bool = true
    ) async -> [String: Double] {
        collector.messages.removeAll { $0.hasPrefix("state:") }
        if !script.isEmpty {
            _ = try? await webView.evaluateJavaScript("\(script); true")
        }
        if resending {
            _ = try? await webView.evaluateJavaScript("window.postMessage('linen-resend', '*'); true")
        }
        var line: String?
        let arrived = await waitUntil {
            line = collector.messages.last { $0.hasPrefix("state:") }
            return line != nil
        }
        #expect(arrived, "the page never reported its state")
        let payload = Data((line ?? "state:{}").dropFirst("state:".count).utf8)
        let fields = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] ?? [:]
        return fields.compactMapValues { ($0 as? NSNumber)?.doubleValue }
    }

    private func audio(_ collector: Collector) async -> String? {
        var line: String?
        _ = await waitUntil {
            line = collector.messages.last { $0.hasPrefix("audio:") }
            return line != nil
        }
        return line
    }

    private func post(_ command: String) -> String {
        "window.postMessage('\(command)', '*')"
    }

    // MARK: - What counts as a length

    /// The live-stream sentinel: WebKit reports `INT64_MAX` microseconds for a
    /// stream, which is finite and passes every ordinary check.
    @Test func aStreamsSentinelLengthIsNotALength() async {
        let (webView, collector) = await player()

        let real = await state(webView, collector, after: "window.__box.duration = 331")
        #expect(real["d"] == 331)
        #expect(real["l"] == 0)

        let sentinel = await state(webView, collector, after: "window.__box.duration = 9223372036854.775")
        #expect(sentinel["d"] == 0, "a sentinel must never be offered as a length")
        #expect(sentinel["l"] == 1, "and the player it came from is live")
    }

    @Test func anEndlessStreamHasNoLengthEither() async {
        let (webView, collector) = await player()

        let endless = await state(webView, collector, after: "window.__box.duration = Infinity")
        #expect(endless["d"] == 0)
        #expect(endless["l"] == 1)
    }

    @Test func aPlayerThatHasNotLoadedIsNotCalledLive() async {
        let (webView, collector) = await player()

        let unknown = await state(webView, collector, after: "window.__box.duration = NaN")
        #expect(unknown["d"] == 0)
        #expect(unknown["l"] == 0)

        let empty = await state(webView, collector, after: "window.__box.duration = 0")
        #expect(empty["d"] == 0)
        #expect(empty["l"] == 0)
    }

    @Test func aNegativeLengthIsNoLength() async {
        let (webView, collector) = await player()

        let backwards = await state(webView, collector, after: "window.__box.duration = -5")
        #expect(backwards["d"] == 0)
    }

    // MARK: - A length that keeps growing

    /// A DVR window reports a real length that rises as the stream runs. One
    /// rise is a seek or a load; it takes a run of them to call the player live.
    @Test func aLengthThatKeepsGrowingIsAStream() async {
        let (webView, collector) = await player()

        let first = await state(webView, collector, after: "window.__box.duration = 100")
        #expect(first["l"] == 0)

        let second = await state(webView, collector, after: "window.__box.duration = 200")
        #expect(second["l"] == 0, "one rise is not a stream")

        let third = await state(webView, collector, after: "window.__box.duration = 300")
        #expect(third["l"] == 1, "a second rise is")
        #expect(third["d"] == 300, "and the length is still reported")
    }

    @Test func aLengthThatSettlesStopsBeingAStream() async {
        let (webView, collector) = await player()

        for length in [100, 200, 300] {
            await state(webView, collector, after: "window.__box.duration = \(length)")
        }
        let held = await state(webView, collector, after: "window.__box.duration = 300")
        #expect(held["l"] == 0)
    }

    @Test func aLengthThatBarelyMovesIsTheSameLength() async {
        let (webView, collector) = await player()

        for length in ["100", "100.1", "100.2"] {
            let step = await state(webView, collector, after: "window.__box.duration = \(length)")
            #expect(step["l"] == 0, "\(length)")
        }
    }

    @Test func aLengthThatFallsStartsTheCountOver() async {
        let (webView, collector) = await player()

        for length in [100, 200] {
            await state(webView, collector, after: "window.__box.duration = \(length)")
        }
        await state(webView, collector, after: "window.__box.duration = 50")
        let after = await state(webView, collector, after: "window.__box.duration = 150")
        #expect(after["l"] == 0, "a fall means a new track, not a longer stream")
    }

    // MARK: - What counts as a sound

    @Test func aPlayingPlayerIsHeard() async {
        let (webView, collector) = await player()

        collector.messages.removeAll()
        await state(webView, collector, after: "window.__box.paused = false")
        #expect(await audio(collector) == "audio:1")
    }

    @Test func aMutedOrSilentPlayerIsNotHeard() async {
        let (webView, collector) = await player()

        collector.messages.removeAll()
        await state(webView, collector, after: "window.__box.paused = false; window.__box.muted = true")
        #expect(await audio(collector) == "audio:0")

        collector.messages.removeAll()
        await state(webView, collector, after: "window.__box.muted = false; window.__box.volume = 0")
        #expect(await audio(collector) == "audio:0")
    }

    @Test func aLoadedPlayerWithNoTrackIsNotHeard() async {
        let (webView, collector) = await player()

        collector.messages.removeAll()
        await state(
            webView,
            collector,
            after: """
                window.__box.paused = false;
                window.__box.readyState = 2;
                window.__box.audioTracks = { length: 0 };
                """
        )
        #expect(await audio(collector) == "audio:0")

        collector.messages.removeAll()
        await state(webView, collector, after: "window.__box.audioTracks = { length: 1 }")
        #expect(await audio(collector) == "audio:1")
    }

    @Test func aPlayerStillLoadingIsTakenAtItsWord() async {
        let (webView, collector) = await player()

        collector.messages.removeAll()
        await state(
            webView,
            collector,
            after: """
                window.__box.paused = false;
                window.__box.readyState = 1;
                window.__box.audioTracks = { length: 0 };
                """
        )
        #expect(await audio(collector) == "audio:1")
    }

    @Test func aTabMutedByTheAppIsStillPlaying() async {
        let (webView, collector) = await player()
        await state(webView, collector, after: "window.__box.paused = false")

        await state(webView, collector, after: post("linen-mute:1"), resending: false)
        collector.messages.removeAll()
        await state(webView, collector)
        #expect(await audio(collector) == "audio:1")
    }

    // MARK: - Driving the player

    @Test func aRelativeSeekStaysInsideTheTrack() async {
        let (webView, collector) = await player()
        await state(webView, collector, after: "window.__box.duration = 100; window.__box.currentTime = 10")

        let back = await state(webView, collector, after: post("linen-seek:-30"), resending: false)
        #expect(back["t"] == 0, "a seek before the start lands on the start")

        let forward = await state(webView, collector, after: post("linen-seek:500"), resending: false)
        #expect(forward["t"] == 100, "and one past the end lands on the end")
    }

    @Test func aProportionalSeekIsReadAgainstTheLength() async {
        let (webView, collector) = await player()
        await state(webView, collector, after: "window.__box.duration = 100")

        let middle = await state(webView, collector, after: post("linen-seekto:0.5"), resending: false)
        #expect(middle["t"] == 50)

        let past = await state(webView, collector, after: post("linen-seekto:2"), resending: false)
        #expect(past["t"] == 100)
    }

    @Test func anAbsoluteSeekIsClampedToo() async {
        let (webView, collector) = await player()
        await state(webView, collector, after: "window.__box.duration = 100")

        let before = await state(webView, collector, after: post("linen-seekabs:-5"), resending: false)
        #expect(before["t"] == 0)

        let after = await state(webView, collector, after: post("linen-seekabs:250"), resending: false)
        #expect(after["t"] == 100)
    }

    @Test func seekingALiveStreamIsNotClampedToNothing() async {
        let (webView, collector) = await player()
        await state(
            webView,
            collector,
            after: "window.__box.duration = Infinity; window.__box.currentTime = 10"
        )

        let moved = await state(webView, collector, after: post("linen-seek:30"), resending: false)
        #expect(moved["t"] == 40)

        let unmoved = await state(webView, collector, after: post("linen-seekto:0.5"), resending: false)
        #expect(unmoved["t"] == 40, "a proportion of no length means nothing")
    }

    @Test func theVolumeCarriesTheMute() async {
        let (webView, collector) = await player()

        let silent = await state(webView, collector, after: post("linen-volume:0"), resending: false)
        #expect(silent["v"] == 0)
        #expect(silent["m"] == 1, "turning it all the way down mutes the player")

        let heard = await state(webView, collector, after: post("linen-volume:0.5"), resending: false)
        #expect(heard["v"] == 0.5)
        #expect(heard["m"] == 0)

        let loud = await state(webView, collector, after: post("linen-volume:4"), resending: false)
        #expect(loud["v"] == 1, "and the volume never goes above one")
    }

    @Test func mutingTheTabMutesThePlayer() async {
        let (webView, collector) = await player()

        let muted = await state(webView, collector, after: post("linen-mute:1"), resending: false)
        #expect(muted["m"] == 1)

        let unmuted = await state(webView, collector, after: post("linen-mute:0"), resending: false)
        #expect(unmuted["m"] == 0)
    }
}
