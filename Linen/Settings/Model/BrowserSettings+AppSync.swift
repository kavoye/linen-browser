// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension BrowserSettings {
    func copyAppSetting(_ key: String, from source: BrowserSettings) {
        switch key {
        case Key.appearance:
            appearance = source.appearance
        case Key.loomStyle:
            loomStyle = source.loomStyle
        case Key.websiteTint:
            matchesWebsiteColor = source.matchesWebsiteColor
        case Key.transparency:
            transparency = source.transparency
        case Key.linkPreview:
            showsLinkPreview = source.showsLinkPreview
        case Key.fullAddress:
            showsFullAddress = source.showsFullAddress
        case Key.linkPeek:
            peeksAtLinks = source.peeksAtLinks
        case Key.mediaPlayer:
            showsMediaPlayer = source.showsMediaPlayer
        case Key.lyrics:
            showsLyrics = source.showsLyrics
        case Key.github:
            showsGitHub = source.showsGitHub
        case Key.tabColorRefraction:
            refractsTabColor = source.refractsTabColor
        case Key.solidSidePanel:
            hasSolidSidePanel = source.hasSolidSidePanel
        case Key.minimal:
            isMinimal = source.isMinimal
        case Key.minimalBar:
            minimalBarEdge = source.minimalBarEdge
        case Key.minimalBarAutoHide:
            minimalBarHiding = source.minimalBarHiding
        case Key.automaticPiP:
            automaticPictureInPicture = source.automaticPictureInPicture
        case Key.videoInPlayer:
            showsVideoInPlayer = source.showsVideoInPlayer
        default:
            copyWebAppSetting(key, from: source)
        }
    }

    private func copyWebAppSetting(_ key: String, from source: BrowserSettings) {
        switch key {
        case Key.pageZoom:
            pageZoom = source.pageZoom
        case Key.tabSleep:
            tabSleep = source.tabSleep
        case Key.archiveTabsAfter:
            archiveTabsAfter = source.archiveTabsAfter
        case Key.downloadFolder:
            downloadFolder = source.downloadFolder
        case Key.askWhereToSave:
            asksWhereToSave = source.asksWhereToSave
        case Key.downloadRetention:
            downloadRetention = source.downloadRetention
        case Key.userAgent:
            userAgentMode = source.userAgentMode
        case Key.customUserAgent:
            customUserAgent = source.customUserAgent
        case Key.webInspector:
            webInspectorEnabled = source.webInspectorEnabled
        case Key.updateChannel:
            updateChannel = source.updateChannel
        case Key.translationTarget:
            translationTargetID = source.translationTargetID
        default:
            break
        }
    }
}
