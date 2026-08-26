// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AVFAudio
import Testing

@testable import Linen

@MainActor
@Suite(.serialized)
struct VoiceInputModelTests {
    @Test func startingBeforePreparationReportsNotReady() {
        let audio = FakeAudioInput()
        let transcriber = FakeTranscriber()
        let model = VoiceInputModel(audio: audio, transcriber: transcriber)
        var failures: [VoiceInputModel.Failure] = []
        model.onFailure = { failures.append($0) }

        model.begin()

        #expect(model.phase == .idle)
        #expect(failures == [.notReady])
        #expect(audio.startCount == 0)
    }

    @Test func aPreparedSessionStreamsAndSubmitsTrimmedSpeech() async throws {
        let audio = FakeAudioInput()
        let transcriber = FakeTranscriber()
        let model = VoiceInputModel(audio: audio, transcriber: transcriber)
        var willBeginCount = 0
        var submitted: [String] = []
        model.onWillBegin = { willBeginCount += 1 }
        model.onUtterance = { text, trace in
            submitted.append(text)
            trace.end()
        }

        try await model.prepare()
        model.begin()
        transcriber.yield("  hello browser  ")
        #expect(await waitUntil { model.transcript == "  hello browser  " })
        await model.finish()

        #expect(model.isReady)
        #expect(model.phase == .idle)
        #expect(model.pipelineState == .idle)
        #expect(willBeginCount == 1)
        #expect(submitted == ["hello browser"])
        #expect(audio.startCount == 1)
        #expect(audio.stopCount == 1)
        #expect(transcriber.finishCount == 1)
    }

    @Test func emptySpeechEndsWithoutSubmitting() async throws {
        let audio = FakeAudioInput()
        let transcriber = FakeTranscriber()
        let model = VoiceInputModel(audio: audio, transcriber: transcriber)
        var submitCount = 0
        model.onUtterance = { _, trace in
            submitCount += 1
            trace.end()
        }

        try await model.prepare()
        model.begin()
        transcriber.yield(" \n ")
        await model.finish()

        #expect(model.phase == .idle)
        #expect(model.transcript.isEmpty)
        #expect(submitCount == 0)
    }

    @Test func cancellationClosesCaptureAndIgnoresLateResults() async throws {
        let audio = FakeAudioInput()
        let transcriber = FakeTranscriber()
        let model = VoiceInputModel(audio: audio, transcriber: transcriber)
        var submitCount = 0
        model.onUtterance = { _, trace in
            submitCount += 1
            trace.end()
        }

        try await model.prepare()
        model.begin()
        transcriber.yield("partial")
        #expect(await waitUntil { model.transcript == "partial" })
        model.cancel()
        transcriber.yield("late")
        try? await Task.sleep(for: .milliseconds(20))

        #expect(model.phase == .idle)
        #expect(model.transcript.isEmpty)
        #expect(submitCount == 0)
        #expect(audio.stopCount == 1)
    }

    @Test func aTranscriptionFailureClosesTheMicrophone() async throws {
        let audio = FakeAudioInput()
        let transcriber = FakeTranscriber()
        let model = VoiceInputModel(audio: audio, transcriber: transcriber)
        var failures: [VoiceInputModel.Failure] = []
        model.onFailure = { failures.append($0) }

        try await model.prepare()
        model.begin()
        transcriber.fail(FixtureError.transcription)

        #expect(await waitUntil { model.phase == .idle })
        #expect(failures == [.transcription])
        #expect(model.transcript.isEmpty)
        #expect(audio.stopCount == 1)
    }

    @Test func aCaptureFailureReturnsToIdle() async throws {
        let audio = FakeAudioInput()
        audio.startError = FixtureError.capture
        let transcriber = FakeTranscriber()
        let model = VoiceInputModel(audio: audio, transcriber: transcriber)
        var failures: [VoiceInputModel.Failure] = []
        model.onFailure = { failures.append($0) }

        try await model.prepare()
        model.begin()

        #expect(model.phase == .idle)
        #expect(failures == [.capture("Fixture capture failure")])
        #expect(audio.startCount == 1)
    }

    @Test func pressingAgainDuringTheReleaseTailContinuesTheSession() async throws {
        let audio = FakeAudioInput()
        let transcriber = FakeTranscriber()
        let model = VoiceInputModel(audio: audio, transcriber: transcriber)

        try await model.prepare()
        model.begin()
        model.scheduleFinish(after: .milliseconds(60))
        model.begin()
        try? await Task.sleep(for: .milliseconds(100))

        #expect(model.phase == .listening)
        #expect(audio.startCount == 1)
        #expect(transcriber.finishCount == 0)
        model.cancel()
    }

    @Test func theReleaseTailFinalizesAndSubmits() async throws {
        let audio = FakeAudioInput()
        let transcriber = FakeTranscriber()
        let model = VoiceInputModel(audio: audio, transcriber: transcriber)
        var submitted: [String] = []
        model.onUtterance = { text, trace in
            submitted.append(text)
            trace.end()
        }

        try await model.prepare()
        model.begin()
        transcriber.yield("finished")
        #expect(await waitUntil { model.transcript == "finished" })
        model.scheduleFinish(after: .zero)

        #expect(await waitUntil { model.phase == .idle })
        #expect(submitted == ["finished"])
        #expect(transcriber.finishCount == 1)
    }

    /// The mic button holds nothing down, so a pause in speech is the only
    /// signal left that the request is finished.
    @Test func silenceAfterTheMicButtonSubmitsOnItsOwn() async throws {
        let audio = FakeAudioInput()
        let transcriber = FakeTranscriber()
        let model = VoiceInputModel(
            audio: audio,
            transcriber: transcriber,
            silenceTail: .milliseconds(60)
        )
        var submitted: [String] = []
        model.onUtterance = { text, trace in
            submitted.append(text)
            trace.end()
        }

        try await model.prepare()
        model.begin(endsOnSilence: true)
        transcriber.yield("open my email")
        #expect(await waitUntil { model.transcript == "open my email" })

        #expect(await waitUntil { model.phase == .idle })
        #expect(submitted == ["open my email"])
        #expect(transcriber.finishCount == 1)
    }

    /// More speech pushes the deadline back. A pause mid-sentence must not cut
    /// the request in half.
    @Test func speakingAgainPostponesTheSilenceCutoff() async throws {
        let audio = FakeAudioInput()
        let transcriber = FakeTranscriber()
        // Six gaps of 300ms against a 1s deadline: 1.8s in total, so the
        // session outlives the tail only if every word pushed it back. The
        // gap is a third of the deadline so that a busy machine delaying a
        // step cannot be mistaken for silence.
        let model = VoiceInputModel(
            audio: audio,
            transcriber: transcriber,
            silenceTail: .seconds(1)
        )

        try await model.prepare()
        model.begin(endsOnSilence: true)
        let words = [
            "open", "open my", "open my email",
            "open my email now", "open my email now please", "open my email now please and",
        ]
        for word in words {
            transcriber.yield(word)
            #expect(await waitUntil { model.transcript == word })
            try? await Task.sleep(for: .milliseconds(300))
            #expect(model.phase == .listening)
        }
        model.cancel()
    }

    /// Holding the talk key keeps its own ending. A long pause mid-sentence
    /// must not send while the key is still down.
    @Test func holdToTalkIgnoresSilence() async throws {
        let audio = FakeAudioInput()
        let transcriber = FakeTranscriber()
        let model = VoiceInputModel(
            audio: audio,
            transcriber: transcriber,
            silenceTail: .milliseconds(40)
        )

        try await model.prepare()
        model.begin()
        transcriber.yield("still thinking")
        #expect(await waitUntil { model.transcript == "still thinking" })
        try? await Task.sleep(for: .milliseconds(140))

        #expect(model.phase == .listening)
        model.cancel()
    }

    @Test func cancellationDuringFinalizationSuppressesTheUtterance() async throws {
        let audio = FakeAudioInput()
        let transcriber = FakeTranscriber()
        transcriber.holdFirstFinish = true
        let model = VoiceInputModel(audio: audio, transcriber: transcriber)
        var submitCount = 0
        model.onUtterance = { _, trace in
            submitCount += 1
            trace.end()
        }

        try await model.prepare()
        model.begin()
        transcriber.yield("do not submit")
        #expect(await waitUntil { model.transcript == "do not submit" })
        let finishing = Task { await model.finish() }
        #expect(await waitUntil { model.phase == .finishing })

        model.begin()
        #expect(model.phase == .finishing)
        #expect(audio.startCount == 1)
        model.cancel()
        transcriber.resumeFirstFinish()
        await finishing.value

        #expect(model.phase == .idle)
        #expect(model.transcript.isEmpty)
        #expect(submitCount == 0)
    }

    @Test func restartingAfterCancellationWaitsForTranscriberCleanup() async throws {
        let audio = FakeAudioInput()
        let transcriber = FakeTranscriber()
        transcriber.holdFirstFinish = true
        let model = VoiceInputModel(audio: audio, transcriber: transcriber)

        try await model.prepare()
        model.begin()
        model.cancel()
        model.begin()

        #expect(audio.startCount == 1)
        #expect(await waitUntil { transcriber.finishCount == 1 })
        transcriber.resumeFirstFinish()
        #expect(await waitUntil { model.phase == .listening })
        #expect(audio.startCount == 2)
        model.cancel()
    }

    private func waitUntil(
        maxSuspensions: Int = 10_000,
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<maxSuspensions {
            if condition() {
                return true
            }
            await Task.yield()
        }
        return condition()
    }
}

@MainActor
private final class FakeAudioInput: AudioInputCapturing {
    var startError: Error?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(targetFormat: AVAudioFormat) throws -> AsyncStream<CapturedAudio> {
        startCount += 1
        if let startError {
            throw startError
        }
        return AsyncStream { _ in }
    }

    func stop() {
        stopCount += 1
    }
}

@MainActor
private final class FakeTranscriber: TranscriberEngine {
    private(set) var bestFormat: AVAudioFormat?
    private(set) var finishCount = 0
    var holdFirstFinish = false

    private var continuation: AsyncThrowingStream<TranscriptUpdate, Error>.Continuation?
    private var firstFinishContinuation: CheckedContinuation<Void, Never>?

    func prepare() async throws {
        bestFormat = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)
    }

    func startSession(input: AsyncStream<CapturedAudio>) -> AsyncThrowingStream<TranscriptUpdate, Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: TranscriptUpdate.self)
        self.continuation = continuation
        return stream
    }

    func finishSession() async throws {
        finishCount += 1
        if holdFirstFinish, finishCount == 1 {
            await withCheckedContinuation { firstFinishContinuation = $0 }
        }
        continuation?.finish()
    }

    func yield(_ text: String) {
        continuation?.yield(TranscriptUpdate(text: text, isFinal: false))
    }

    func fail(_ error: Error) {
        continuation?.finish(throwing: error)
    }

    func resumeFirstFinish() {
        firstFinishContinuation?.resume()
        firstFinishContinuation = nil
    }
}

private enum FixtureError: LocalizedError {
    case capture
    case transcription

    var errorDescription: String? {
        switch self {
        case .capture:
            "Fixture capture failure"
        case .transcription:
            "Fixture transcription failure"
        }
    }
}
