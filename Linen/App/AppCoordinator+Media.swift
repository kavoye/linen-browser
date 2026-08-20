// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension AppCoordinator {
    // MARK: - Media following the tab you're looking at

    func followMedia(to newTab: BrowserTab?, from previousTab: BrowserTab?) {
        mediaClaim += 1
        let claim = mediaClaim

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

    private func hasPlayedItsCurrentPage(_ tab: BrowserTab) -> Bool {
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

    func toggleMute(tab: BrowserTab) {
        tab.isMuted.toggle()
        MediaCenter.setMuted(tab.isMuted, on: tab.webView)
        guard media.controlledTabID == tab.id else { return }
        media.model.isMuted = tab.isMuted
    }
}
