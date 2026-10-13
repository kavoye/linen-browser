// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

@MainActor
@Observable
final class ReaderListener {
    enum State: Equatable {
        case idle
        case playing
        case paused
    }

    private struct Utterance {
        let block: Int
        let text: String
    }

    private(set) var state = State.idle
    private(set) var tabID: UUID?
    private(set) var block: Int?

    nonisolated static let rateRange: ClosedRange<Float> = 0.5...1.5

    private(set) var rate: Float

    @ObservationIgnored var onWillStart: (() -> Void)?
    @ObservationIgnored private let output: any SpeechOutput
    @ObservationIgnored private let defaults: UserDefaults
    private static let rateKey = "readerSpeechRate"
    @ObservationIgnored private var utterances: [Utterance] = []
    @ObservationIgnored private var position = 0
    @ObservationIgnored private var awaitingStart = false

    init(output: any SpeechOutput, defaults: UserDefaults = .standard) {
        self.output = output
        self.defaults = defaults
        let stored = defaults.object(forKey: Self.rateKey) as? Float ?? 1
        rate = Self.rounded(stored)
        output.setRate(rate)
        output.onSpeakingChange = { [weak self] speaking in
            self?.speakingChanged(speaking)
        }
    }

    func setRate(_ rate: Float) {
        self.rate = Self.rounded(rate)
        output.setRate(self.rate)
        defaults.set(self.rate, forKey: Self.rateKey)
    }

    private static func rounded(_ rate: Float) -> Float {
        (min(max(rate, rateRange.lowerBound), rateRange.upperBound) * 10).rounded() / 10
    }

    func isListening(to tabID: UUID) -> Bool {
        state != .idle && self.tabID == tabID
    }

    func start(_ article: ReaderArticle, in tab: BrowserTab) {
        stop()
        onWillStart?()
        let title = article.title.isEmpty ? [] : [Utterance(block: ReaderPage.titleBlock, text: article.title)]
        utterances = title + article.blocks.enumerated().flatMap { index, text in
            OpenAISpeechOutput.chunks(text).map { Utterance(block: index, text: $0) }
        }
        guard !utterances.isEmpty else { return }
        position = 0
        let id = tab.id
        tabID = id
        tab.reader.onDeactivate = { [weak self] in
            guard let self, tabID == id else { return }
            stop()
        }
        state = .playing
        speakCurrent()
    }

    func togglePause() {
        switch state {
        case .playing:
            state = .paused
            output.stopSpeaking()
        case .paused:
            state = .playing
            speakCurrent()
        case .idle:
            break
        }
    }

    func skip(by delta: Int) {
        guard state != .idle, !utterances.isEmpty else { return }
        position = min(max(0, position + delta), utterances.count - 1)
        block = utterances[position].block
        if state == .playing {
            speakCurrent()
        }
    }

    var canSkipBack: Bool {
        state != .idle && position > 0
    }

    var canSkipForward: Bool {
        state != .idle && position < utterances.count - 1
    }

    func stop() {
        guard state != .idle else { return }
        state = .idle
        tabID = nil
        block = nil
        utterances = []
        position = 0
        awaitingStart = false
        output.stopSpeaking()
    }

    private func speakCurrent() {
        guard utterances.indices.contains(position) else {
            stop()
            return
        }
        let utterance = utterances[position]
        block = utterance.block
        awaitingStart = true
        output.stopSpeaking()
        output.speak(utterance.text)
    }

    private func speakingChanged(_ speaking: Bool) {
        guard state == .playing else { return }
        if speaking {
            awaitingStart = false
            return
        }
        guard !awaitingStart else { return }
        position += 1
        speakCurrent()
    }
}
