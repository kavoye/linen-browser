// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension MediaModel {
    func applyTiming(_ fields: [String: Double]) {
        let live = fields["l"] == 1
        if let time = fields["t"], abs(time - currentTime) > 0.05 {
            currentTime = time
        }
        if let reported = fields["d"], reported > 0, reported != duration {
            duration = reported
        }
        if live {
            if !isLive {
                isLive = true
            }
        } else if isLive, let reported = fields["d"], reported > 0 {
            isLive = false
        }
        if let playing = fields["p"] {
            let nowPlaying = playing == 1
            if nowPlaying != isPlaying {
                isPlaying = nowPlaying
            }
        }
        if let level = fields["v"], abs(level - volume) > 0.005 {
            volume = level
        }
        if let muted = fields["m"] {
            let nowMuted = muted == 1
            if nowMuted != isMuted {
                isMuted = nowMuted
            }
        }
    }

    func applyTrack(_ fields: [String: String]) {
        let track = fields["t"] ?? ""
        let performer = fields["a"] ?? ""
        let record = fields["al"] ?? ""
        if trackTitle != track {
            trackTitle = track
        }
        if artist != performer {
            artist = performer
        }
        if album != record {
            album = record
        }
        if !track.isEmpty {
            title = performer.isEmpty ? track : "\(track) — \(performer)"
        }
    }
}
