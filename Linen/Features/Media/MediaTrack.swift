// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct MediaTrack {
    let title: String
    let pageTitle: String
    let trackTitle: String
    let artist: String
    let album: String
    let artworkURL: URL?
    let currentTime: Double
    let duration: Double
    let isLive: Bool
    let isPlaying: Bool

    init(_ model: MediaModel) {
        title = model.title
        pageTitle = model.pageTitle
        trackTitle = model.trackTitle
        artist = model.artist
        album = model.album
        artworkURL = model.artworkURL
        currentTime = model.currentTime
        duration = model.duration
        isLive = model.isLive
        isPlaying = model.isPlaying
    }

    func apply(to model: MediaModel) {
        model.title = title
        model.pageTitle = pageTitle
        model.trackTitle = trackTitle
        model.artist = artist
        model.album = album
        model.artworkURL = artworkURL ?? model.artworkURL
        model.currentTime = currentTime
        model.duration = duration
        model.isLive = isLive
        model.isPlaying = isPlaying
    }
}
