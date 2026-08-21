// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os
import QuartzCore

nonisolated struct LyricsSignature: Equatable, Sendable {
    var tabID: UUID?
    var title: String
    var artist: String
    var album: String
    var seconds: Int
    var isEnabled: Bool
    var isPrivate: Bool
    var isLive: Bool

    var isPlayable: Bool {
        isEnabled && !isPrivate && tabID != nil && !isLive && !title.isEmpty && seconds > 0
    }
}

nonisolated enum LyricsPhase: Equatable {
    case idle
    case off
    case looking
    case words(LyricsTrack)
    case instrumental
    case missing
}

@MainActor
@Observable
final class LyricsModel {
    private(set) var phase: LyricsPhase = .idle
    private(set) var alternatives: [LyricsMatch] = []
    private(set) var matched: LyricsMatch?
    private(set) var activeIndex: Int?
    private(set) var isFindingAlternatives = false
    var offset: Double = 0 {
        didSet { retime() }
    }

    var isOnScreen = false {
        didSet {
            guard isOnScreen != oldValue else { return }
            if isOnScreen {
                startTicking()
            } else {
                stopTicking()
            }
        }
    }

    var textSize: LyricsTextSize {
        didSet {
            guard textSize != oldValue else { return }
            defaults.set(textSize.rawValue, forKey: Key.textSize)
        }
    }

    private enum Key {
        static let textSize = "lyrics.textSize"
    }

    static let offsetStep: Double = 0.25
    static let widestOffset: Double = 10

    @ObservationIgnored private let source: any LyricsSource
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var anchorMedia: Double = 0
    @ObservationIgnored private var anchorHost: Double = 0
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var queries: [LyricsQuery] = []
    @ObservationIgnored private var signature = LyricsSignature(
        tabID: nil, title: "", artist: "", album: "",
        seconds: 0, isEnabled: false, isPrivate: false, isLive: false
    )

    init(source: any LyricsSource = LRCLIB(), defaults: UserDefaults = .standard) {
        self.source = source
        self.defaults = defaults
        textSize = defaults.string(forKey: Key.textSize)
            .flatMap(LyricsTextSize.init(rawValue:)) ?? .huge
    }

    var lines: [LyricsLine] {
        guard case let .words(track) = phase else { return [] }
        return track.lines
    }

    var plainText: String? {
        guard case let .words(track) = phase, track.lines.isEmpty else { return nil }
        let text = track.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    var isSynced: Bool {
        !lines.isEmpty
    }

    // MARK: - Playback time

    func sync(time: Double, isPlaying: Bool) {
        anchorMedia = time
        anchorHost = CACurrentMediaTime()
        isRunning = isPlaying
        retime()
    }

    func elapsed(at host: Double = CACurrentMediaTime()) -> Double {
        let raw = isRunning ? anchorMedia + (host - anchorHost) : anchorMedia
        return raw - offset
    }

    private func retime() {
        let found = LyricsParser.index(at: elapsed(), in: lines)
        if found != activeIndex {
            activeIndex = found
        }
    }

    private func startTicking() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(60))
                guard let self else { return }
                retime()
            }
        }
    }

    private func stopTicking() {
        ticker?.cancel()
        ticker = nil
    }

    // MARK: - Looking a track up

    func load(_ next: LyricsSignature) async {
        signature = next
        queries = []
        alternatives = []
        isFindingAlternatives = false
        matched = nil
        activeIndex = nil
        offset = 0

        guard next.isEnabled else {
            phase = .off
            return
        }
        guard next.isPlayable else {
            phase = .idle
            Pipeline.log.notice("""
            lyrics: nothing to look up — tab \(next.tabID != nil), title \(!next.title.isEmpty),             seconds \(next.seconds), live \(next.isLive), private \(next.isPrivate)
            """)
            return
        }

        let queries = LyricsNaming.queries(
            title: next.title,
            artist: next.artist,
            album: next.album,
            duration: Double(next.seconds)
        )
        guard !queries.isEmpty else {
            phase = .missing
            return
        }

        self.queries = queries
        phase = .looking
        let fetch = await source.lyrics(for: queries)
        guard signature == next else { return }

        alternatives = fetch.alternatives
        guard let best = fetch.best else {
            phase = .missing
            return
        }
        adopt(best, duration: Double(next.seconds))
    }

    func findAlternatives() async {
        guard !isFindingAlternatives, let query = queries.first else { return }
        let asked = signature
        isFindingAlternatives = true
        let found = await source.alternatives(for: query)
        guard signature == asked else { return }
        isFindingAlternatives = false
        alternatives = found
    }

    func use(_ match: LyricsMatch) {
        adopt(match, duration: Double(signature.seconds))
    }

    private func adopt(_ match: LyricsMatch, duration: Double) {
        matched = match
        if match.isInstrumental || !match.hasWords {
            phase = .instrumental
            activeIndex = nil
            return
        }
        phase = .words(match.track(matching: duration))
        retime()
    }

    // MARK: - Nudging the timing

    func nudge(by seconds: Double) {
        let next = (offset + seconds).clamped(to: -Self.widestOffset...Self.widestOffset)
        offset = (next / Self.offsetStep).rounded() * Self.offsetStep
    }

    func resetOffset() {
        offset = 0
    }
}

extension Comparable {
    fileprivate func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
