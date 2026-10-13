// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension AppCoordinator {
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
            pinned: mediaDock.lyricsPinnedTabID,
            active: browser.activeTabID,
            docked: media.controlledTabID,
            held: mediaDock.lyricsHeldTabID,
            candidates: candidates.map(\.id)
        ) else { return nil }
        return candidates.first { $0.id == id }
    }

    func pinLyrics(to tab: BrowserTab) {
        mediaDock.lyricsPinnedTabID = tab.id
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
}
