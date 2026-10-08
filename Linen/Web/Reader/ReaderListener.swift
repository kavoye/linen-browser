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

    @ObservationIgnored var onWillStart: (() -> Void)?
    @ObservationIgnored private let output: any SpeechOutput
    @ObservationIgnored private var utterances: [Utterance] = []
    @ObservationIgnored private var position = 0
    @ObservationIgnored private var awaitingStart = false

    init(output: any SpeechOutput) {
        self.output = output
        output.onSpeakingChange = { [weak self] speaking in
            self?.speakingChanged(speaking)
        }
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
