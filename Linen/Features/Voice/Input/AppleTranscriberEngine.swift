// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AVFAudio
import os
import Speech

@MainActor
final class AppleTranscriberEngine: TranscriberEngine {
    private(set) var bestFormat: AVAudioFormat?

    private var locale = Locale(identifier: "en_US")
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?

    func prepare() async throws {
        if let supported = await SpeechTranscriber.supportedLocale(equivalentTo: .current) {
            locale = supported
        }
        let probe = Self.makeTranscriber(locale: locale)

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [probe]) {
            Pipeline.log.notice("Downloading speech assets for \(self.locale.identifier, privacy: .public)…")
            try await request.downloadAndInstall()
            Pipeline.log.notice("Speech assets installed")
        }

        bestFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [probe])
        guard bestFormat != nil else { throw TranscriberError.noAudioFormat }
    }

    func startSession(input: AsyncStream<CapturedAudio>) -> AsyncThrowingStream<TranscriptUpdate, Error> {
        let transcriber = Self.makeTranscriber(locale: locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.transcriber = transcriber
        self.analyzer = analyzer

        let (stream, continuation) = AsyncThrowingStream.makeStream(of: TranscriptUpdate.self)

        Task {
            var committed = ""
            do {
                try await analyzer.start(inputSequence: input.map { AnalyzerInput(buffer: $0.buffer) })
                for try await result in transcriber.results {
                    let piece = String(result.text.characters)
                    if result.isFinal {
                        committed += piece
                        continuation.yield(TranscriptUpdate(text: committed, isFinal: false))
                    } else {
                        continuation.yield(TranscriptUpdate(text: committed + piece, isFinal: false))
                    }
                }
                continuation.yield(TranscriptUpdate(text: committed, isFinal: true))
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        return stream
    }

    func finishSession() async throws {
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
        analyzer = nil
        transcriber = nil
    }

    private static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
    }
}

enum TranscriberError: Error {
    case noAudioFormat
}
