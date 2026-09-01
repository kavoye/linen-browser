// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import os
import WebKit

extension AppCoordinator {
    // MARK: - Media following the tab you're looking at

    func followMedia(to newTab: BrowserTab?, from previousTab: BrowserTab?) {
        mediaClaim += 1
        let claim = mediaClaim
        returnPictureToTheTabInFront()

        if let newTab, media.controlledTabID == newTab.id {
            media.releaseControl()
            dockSuccessor(to: newTab.id)
        }
        if let previousTab, browser.isVisibleInSplit(previousTab) {
            if media.controlledTabID == previousTab.id {
                media.releaseControl()
                dockSuccessor(to: previousTab.id)
            }
            return
        }

        guard let previousTab, previousTab.id != newTab?.id else { return }
        Task { [weak self] in
            guard let self,
                  await BrowserModel.isPlayingMedia(previousTab.webView),
                  claim == mediaClaim,
                  browser.activeTabID != previousTab.id,
                  !browser.isVisibleInSplit(previousTab),
                  !previousTab.isMuted
            else { return }
            controlPlayback(in: previousTab)
            if settings.automaticPictureInPicture {
                media.requestNativePiP(on: previousTab.webView)
            }
        }
    }

    /// The picture is borrowed only for the experiment that shows it, and never
    /// while video leaves for the floating window on its own.
    func applyPictureLending() {
        media.lendsPicture = settings.showsVideoInPlayer && !settings.automaticPictureInPicture
    }

    /// The video needs somewhere on screen to land, or WebKit will not let go
    /// of it. The card counts as somewhere, so a lent picture stays put.
    func makeRoomForPicture(in webView: WKWebView?) {
        if let webView, webView !== media.model.pictureWebView,
           let tab = browser.tabs.first(where: { $0.isMaterialised && $0.webView === webView }) {
            openTab(tab)
        }
        showBrowser()
    }

    /// What left on its own comes back on its own: looking at the tab again is
    /// the same answer as the floating window's return button.
    func returnPictureToTheTabInFront() {
        guard settings.automaticPictureInPicture, browserVisible, !isShowingSettings else { return }
        let inFront = browser.tabs.filter {
            $0.id == browser.activeTabID || browser.isVisibleInSplit($0)
        }
        guard let tab = inFront.first(where: { media.isPictureOut($0.webView) }) else { return }
        Pipeline.log.notice("media: its tab is in front again, putting the picture back")
        media.exitPictureInPicture(for: tab.webView)
    }

    func togglePictureInPicture(for tab: BrowserTab) {
        media.togglePictureInPicture(for: tab.webView)
    }

    func moveVideoToPictureInPicture() {
        guard settings.automaticPictureInPicture else { return }
        let active = browser.activeTab
        guard let id = MediaRoster.pictureTarget(
            active: active.flatMap { $0.internalPage == nil ? $0.id : nil },
            isActivePlaying: active.map { $0.isPlayingAudio && !$0.isMuted } ?? false,
            docked: media.controlledTabID,
            isDockedPlaying: media.model.isPlaying
        ),
            let tab = browser.tabs.first(where: { $0.id == id }), !tab.isDeferred
        else { return }
        media.requestNativePiP(on: tab.webView)
    }

    func wireMedia() {
        media.onPictureChanged = { [weak self] in self?.applyHoverShield() }
        media.onControlledTabChanged = { [weak self] previousID, currentID in
            guard let self else { return }
            if let previousID, let tab = browser.tabs.first(where: { $0.id == previousID }) {
                tab.isControlledByMediaDock = false
            }
            if let currentID, let tab = browser.tabs.first(where: { $0.id == currentID }) {
                tab.isControlledByMediaDock = true
            }
        }
        media.onTabAudioChanged = { [weak self] webView, isPlaying in
            guard let self, let tab = browser.tabs.first(where: { $0.isMaterialised && $0.webView === webView }) else { return }
            guard tab.isPlayingAudio != isPlaying else { return }
            tab.isPlayingAudio = isPlaying
            if isPlaying {
                playedPages[tab.id] = tab.urlString
            }
            if isPlaying, !tab.isMuted, tab.id != browser.activeTabID,
               media.controlledTabID == nil {
                controlPlayback(in: tab)
            }
        }
        media.onTabUnmuted = { [weak self] webView in
            guard let self, let tab = browser.tabs.first(where: { $0.isMaterialised && $0.webView === webView }),
                  tab.isMuted
            else { return }
            tab.isMuted = false
            if media.controlledTabID == tab.id {
                media.model.isMuted = false
            }
        }
        media.onTabVideoChanged = { [weak self] webView, hasVideo in
            guard let self, let tab = browser.tabs.first(where: { $0.isMaterialised && $0.webView === webView }),
                  tab.hasVideo != hasVideo
            else { return }
            tab.hasVideo = hasVideo
        }
        media.onPictureOutChanged = { [weak self] webView, isOut in
            guard let self, let tab = browser.tabs.first(where: { $0.isMaterialised && $0.webView === webView }),
                  tab.isPictureOut != isOut
            else { return }
            tab.isPictureOut = isOut
        }
        media.onReturnedInline = { [weak self] webView in
            guard let self else { return }
            Pipeline.log.notice("media: the picture came home, making room for it")
            makeRoomForPicture(in: webView)
        }
        browser.onContentProcessTerminated = { [weak self] tab in
            tab.hasVideo = false
            self?.media.pageDidReset(tab.webView)
        }
        browser.onPictureInPictureChanged = { [weak self] tab, isOut in
            Pipeline.log.notice("media: WebKit reports the picture \(isOut ? "out" : "home", privacy: .public)")
            self?.media.setPictureInPicture(isOut, for: tab.webView, source: .webKit)
        }
        browser.onPictureReturnExpected = { [weak self] tab in
            guard let self, media.notePictureReturnAsk(for: tab.webView) else { return }
            Pipeline.log.notice("media: the floating window wants to hand the video back")
            makeRoomForPicture(in: tab.webView)
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.moveVideoToPictureInPicture()
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.returnPictureToTheTabInFront()
            }
        }
    }

    var mediaRoster: [BrowserTab] {
        browser.tabs.filter { tab in
            MediaRoster.isCandidate(
                isPlayingAudio: tab.isPlayingAudio,
                isMuted: tab.isMuted,
                isInternalPage: tab.internalPage != nil,
                isActive: tab.id == browser.activeTabID,
                isVisibleInSplit: browser.isVisibleInSplit(tab),
                isDocked: media.controlledTabID == tab.id
            )
        }
    }

    var mediaPickerTabs: [BrowserTab] {
        browser.tabs.filter { tab in
            MediaRoster.isPickerItem(
                isPlayingAudio: tab.isPlayingAudio,
                isMuted: tab.isMuted,
                isInternalPage: tab.internalPage != nil,
                isActive: tab.id == browser.activeTabID,
                isVisibleInSplit: browser.isVisibleInSplit(tab),
                isDocked: media.controlledTabID == tab.id,
                hasPlayed: hasPlayedItsCurrentPage(tab)
            )
        }
    }

    func hasPlayedItsCurrentPage(_ tab: BrowserTab) -> Bool {
        !tab.isDeferred && playedPages[tab.id] == tab.urlString
    }

    func dockMedia(_ tab: BrowserTab) {
        dock(tab, claiming: true)
    }

    func dockSuccessor(to previous: UUID) {
        guard let id = MediaRoster.successor(to: previous, in: mediaRoster.map(\.id)),
              let tab = browser.tabs.first(where: { $0.id == id })
        else { return }
        dock(tab, claiming: false)
    }

    private func dock(_ tab: BrowserTab, claiming: Bool) {
        guard media.controlledTabID != tab.id else { return }
        if claiming {
            mediaClaim += 1
        }
        controlPlayback(in: tab)
    }

    func controlPlayback(in tab: BrowserTab) {
        media.controlTab(
            webView: tab.webView,
            title: tab.title,
            tabID: tab.id,
            isPlaying: tab.isPlayingAudio,
            artwork: MediaCenter.poster(forPage: tab.urlString)
        )
    }

    var dockedTab: BrowserTab? {
        guard let tabID = media.controlledTabID else { return nil }
        return browser.tabs.first { $0.id == tabID }
    }

    var isDockedTabPrivate: Bool {
        dockedTab?.isPrivate ?? false
    }

    var lyricsPickerTabs: [BrowserTab] {
        browser.tabs.filter { tab in
            MediaRoster.isLyricsSource(
                isPlayingAudio: tab.isPlayingAudio || media.controlledTabID == tab.id,
                hasPlayed: hasPlayedItsCurrentPage(tab),
                isInternalPage: tab.internalPage != nil,
                isDeferred: tab.isDeferred
            )
        }
    }

    var lyricsTab: BrowserTab? {
        let candidates = lyricsPickerTabs
        guard let id = MediaRoster.lyricsOwner(
            pinned: lyricsPinnedTabID,
            active: browser.activeTabID,
            docked: media.controlledTabID,
            candidates: candidates.map(\.id)
        ) else { return nil }
        return candidates.first { $0.id == id }
    }

    func pinLyrics(to tab: BrowserTab) {
        lyricsPinnedTabID = tab.id
    }

    var isLyricsSourceDocked: Bool {
        guard let tab = lyricsTab else { return false }
        return tab.id == media.controlledTabID && media.model.isActive
    }

    var lyricsSource: MediaModel {
        isLyricsSourceDocked ? media.model : media.watched
    }

    var isLyricsTabPrivate: Bool {
        lyricsTab?.isPrivate ?? false
    }

    var showsLyrics: Bool {
        settings.showsLyrics && lyricsTab != nil && !lyricsSource.isLive
    }

    var hasLyrics: Bool {
        guard showsLyrics else { return false }
        if case .words = lyrics.phase {
            return true
        }
        return false
    }

    func toggleLyrics() {
        guard settings.showsLyrics else { return }
        if !browserVisible {
            showBrowser()
        }
        sidePanel.toggle(.lyrics)
    }

    func watchForLyrics(_ tab: BrowserTab?) {
        guard let tab, settings.showsLyrics, !tab.isPrivate,
              tab.id != media.controlledTabID || !media.model.isActive
        else {
            media.stopWatching()
            return
        }
        media.watch(
            webView: tab.webView,
            title: tab.title,
            tabID: tab.id,
            artwork: MediaCenter.poster(forPage: tab.urlString)
        )
    }

    func toggleMute(tab: BrowserTab) {
        tab.isMuted.toggle()
        MediaCenter.setMuted(tab.isMuted, on: tab.webView)
        guard media.controlledTabID == tab.id else { return }
        media.model.isMuted = tab.isMuted
    }
}
