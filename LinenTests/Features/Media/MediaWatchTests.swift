// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

/// The lyrics view follows the tab you are looking at, which the dock never
/// takes over. That second reading has to reach `watched` and stop at the
/// docked model.
@MainActor
@Suite(.boundedWebViews)
struct MediaWatchTests {
    private func state(time: Double, duration: Double, playing: Bool = true) -> String {
        "state:{\"t\":\(time),\"d\":\(duration),\"l\":0,\"p\":\(playing ? 1 : 0),\"v\":1,\"m\":0,\"w\":640}"
    }

    @Test func aWatchedTabReportsItsOwnTimeAndTrack() {
        let media = MediaCenter()
        let page = WKWebView()

        media.watch(webView: page, title: "Adele - Easy On Me", tabID: UUID(), artwork: nil)
        media.receiveScriptMessage(state(time: 128, duration: 331), from: page, isMainFrame: true)
        media.receiveScriptMessage(
            "meta:{\"t\":\"Easy On Me\",\"a\":\"Adele\",\"al\":\"30\",\"art\":\"\",\"g\":\"0\"}",
            from: page,
            isMainFrame: true
        )

        #expect(media.watched.isActive)
        #expect(media.watched.currentTime == 128)
        #expect(media.watched.duration == 331)
        #expect(media.watched.isPlaying)
        #expect(media.watched.trackTitle == "Easy On Me")
        #expect(media.watched.artist == "Adele")
        #expect(media.watched.album == "30")
    }

    @Test func theDockedModelIsLeftAloneByAWatchedTab() {
        let media = MediaCenter()
        let page = WKWebView()

        media.watch(webView: page, title: "Adele", tabID: UUID(), artwork: nil)
        media.receiveScriptMessage(state(time: 128, duration: 331), from: page, isMainFrame: true)

        #expect(media.model.currentTime == 0)
        #expect(media.model.duration == 0)
        #expect(!media.model.isActive)
    }

    @Test func aReleasedTabStopsBeingRead() {
        let media = MediaCenter()
        let page = WKWebView()
        media.watch(webView: page, title: "Adele", tabID: UUID(), artwork: nil)
        media.receiveScriptMessage(state(time: 30, duration: 331), from: page, isMainFrame: true)

        media.stopWatching()
        media.receiveScriptMessage(state(time: 90, duration: 331), from: page, isMainFrame: true)

        #expect(media.watched.currentTime == 30)
        #expect(!media.watched.isActive)
    }

    @Test func anotherTabIsNeverMistakenForTheWatchedOne() {
        let media = MediaCenter()
        let page = WKWebView()
        let other = WKWebView()
        media.watch(webView: page, title: "Adele", tabID: UUID(), artwork: nil)

        media.receiveScriptMessage(state(time: 90, duration: 331), from: other, isMainFrame: true)

        #expect(media.watched.currentTime == 0)
    }

    @Test func aSubframeNeverMovesTheClock() {
        let media = MediaCenter()
        let page = WKWebView()
        media.watch(webView: page, title: "Adele", tabID: UUID(), artwork: nil)

        media.receiveScriptMessage(state(time: 90, duration: 331), from: page, isMainFrame: false)

        #expect(media.watched.currentTime == 0)
    }

    @Test func watchingASecondTabForgetsTheFirst() {
        let media = MediaCenter()
        let first = WKWebView()
        let second = WKWebView()
        media.watch(webView: first, title: "One", tabID: UUID(), artwork: nil)
        media.receiveScriptMessage(state(time: 30, duration: 331), from: first, isMainFrame: true)

        media.watch(webView: second, title: "Two", tabID: UUID(), artwork: nil)

        #expect(media.watched.currentTime == 0)
        #expect(media.watched.title == "Two")
        media.receiveScriptMessage(state(time: 12, duration: 200), from: first, isMainFrame: true)
        #expect(media.watched.currentTime == 0)
    }

    @Test func theScriptCanBeAskedToRepeatItself() {
        #expect(MediaCenter.frameScriptSource.contains("linen-resend"))
    }
}
