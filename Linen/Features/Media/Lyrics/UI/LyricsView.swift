// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct LyricsSurface: View {
    let coordinator: AppCoordinator

    private var media: MediaCenter {
        coordinator.media
    }
    private var lyrics: LyricsModel {
        coordinator.lyrics
    }
    private var model: MediaModel {
        coordinator.lyricsSource
    }

    private var signature: LyricsSignature {
        LyricsSignature(
            tabID: model.controlledTabID,
            title: model.trackTitle.isEmpty ? model.pageTitle : model.trackTitle,
            artist: model.artist,
            album: model.album,
            seconds: Int(model.duration.rounded()),
            isEnabled: coordinator.settings.showsLyrics,
            isPrivate: coordinator.isLyricsTabPrivate,
            isLive: model.isLive
        )
    }

    private var title: String {
        if let matched = lyrics.matched, !matched.track.isEmpty {
            return matched.track
        }
        return model.trackTitle.isEmpty ? model.title : model.trackTitle
    }

    private var isOnScreen: Bool {
        coordinator.sidePanel.isShowing(.lyrics) && !coordinator.isShowingSettings
    }

    private var subtitle: String {
        let matched = lyrics.matched
        let artist = matched?.artist.isEmpty == false ? matched!.artist : model.artist
        let album = matched?.album.isEmpty == false ? matched!.album : model.album
        if artist.isEmpty {
            return album
        }
        let repeats = album.isEmpty || album == artist || album == title
        return repeats ? artist : "\(artist) · \(album)"
    }

    var body: some View {
        let watching = isOnScreen ? coordinator.lyricsTab : nil
        let watch = LyricsWatch(
            tabID: watching?.id,
            isDocked: coordinator.isLyricsSourceDocked,
            isOnScreen: isOnScreen
        )
        let lookup = LyricsLookup(signature: signature, isOnScreen: isOnScreen)
        LyricsBoard(
            lyrics: lyrics,
            title: title,
            subtitle: subtitle,
            artwork: model.artworkURL,
            isPlaying: model.isPlaying,
            sources: coordinator.lyricsPickerTabs,
            chosen: watching?.id,
            onChoose: coordinator.pinLyrics(to:),
            onSeek: seek(to:)
        )
        .task(id: lookup) {
            guard lookup.isOnScreen else { return }
            await lyrics.load(lookup.signature)
        }
        .task(id: watch) { coordinator.watchForLyrics(watching) }
        .onChange(of: model.currentTime, initial: true) { follow() }
        .onChange(of: model.isPlaying) { follow() }
        .onAppear { lyrics.isOnScreen = isOnScreen }
        .onChange(of: isOnScreen, initial: false) { _, showing in lyrics.isOnScreen = showing }
        .onDisappear {
            lyrics.isOnScreen = false
            coordinator.mediaDock.lyricsPinnedTabID = nil
            coordinator.media.stopWatching()
        }
    }

    private func follow() {
        lyrics.sync(time: model.currentTime, isPlaying: model.isPlaying)
    }

    private func seek(to line: LyricsLine) {
        guard model.duration > 0 else { return }
        let seconds = min(max(line.start + lyrics.offset, 0), model.duration)
        if coordinator.isLyricsSourceDocked {
            media.seek(toFraction: seconds / model.duration)
        } else if let tab = coordinator.lyricsTab {
            MediaCenter.seek(to: seconds, on: tab.webView)
        }
    }
}

private struct LyricsWatch: Equatable {
    var tabID: UUID?
    var isDocked: Bool
    var isOnScreen: Bool
}

enum LyricsStageKind {
    case idle, off, looking, words, instrumental, missing, live
}

private struct LyricsLookup: Equatable {
    var signature: LyricsSignature
    var isOnScreen: Bool
}

struct LyricsBackdrop: View {
    let artwork: URL?

    var body: some View {
        Color.black
            .overlay {
                if let artwork {
                    AsyncImage(url: artwork) { phase in
                        if case let .success(image) = phase {
                            image
                                .resizable()
                                .scaledToFill()
                                .blur(radius: 70)
                                .saturation(1.5)
                                .scaleEffect(1.4)
                                .opacity(0.55)
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
            .overlay {
                LinearGradient(
                    colors: [.black.opacity(0.45), .black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipped()
            .drawingGroup()
    }
}
