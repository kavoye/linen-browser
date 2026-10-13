// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation
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
    var canGoToPreviousTrack = false
    var canGoToNextTrack = false

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
