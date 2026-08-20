// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AVFAudio
import Observation
import os

@MainActor
protocol AudioInputCapturing: AnyObject {
    func start(targetFormat: AVAudioFormat) throws -> AsyncStream<CapturedAudio>
    func stop()
}

extension AudioCaptureService: AudioInputCapturing {}

@MainActor
@Observable
final class VoiceInputModel {
    enum Phase: Equatable {
        case idle
        case listening
        case finishing
    }

    enum Failure: Equatable {
        case notReady
        case capture(String)
        case transcription
    }

    private(set) var phase: Phase = .idle
    private(set) var transcript = ""
    private(set) var isReady = false

    @ObservationIgnored private let audio: any AudioInputCapturing
    @ObservationIgnored private let transcriber: any TranscriberEngine
    @ObservationIgnored private let releaseTail: Duration
    @ObservationIgnored private let silenceTail: Duration
    @ObservationIgnored private var sessionTask: Task<Void, Never>?
    @ObservationIgnored private var releaseTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isFinalizingSession = false
    @ObservationIgnored private var beginAfterFinalization = false
    @ObservationIgnored private var endsOnSilence = false
    @ObservationIgnored private var deferredEndsOnSilence = false

    @ObservationIgnored var onWillBegin: (() -> Void)?
    @ObservationIgnored var onFailure: ((Failure) -> Void)?
    @ObservationIgnored var onUtterance: ((String, LatencyTrace) -> Void)?

    init(
        audio: any AudioInputCapturing = AudioCaptureService(),
        transcriber: any TranscriberEngine = AppleTranscriberEngine(),
        releaseTail: Duration = .milliseconds(450),
        silenceTail: Duration = .seconds(4)
    ) {
        self.audio = audio
        self.transcriber = transcriber
        self.releaseTail = releaseTail
        self.silenceTail = silenceTail
    }

    var pipelineState: PipelineState {
        switch phase {
        case .idle:
            .idle
        case .listening:
            .listening
        case .finishing:
            .executing
        }
    }

    func prepare() async throws {
        try await transcriber.prepare()
        isReady = true
    }

    func begin(endsOnSilence: Bool = false) {
        releaseTask?.cancel()
        releaseTask = nil
        if isFinalizingSession, phase == .idle {
            beginAfterFinalization = true
            deferredEndsOnSilence = endsOnSilence
            return
        }
        guard phase != .listening else { return }
        guard phase == .idle else { return }
        guard isReady, let format = transcriber.bestFormat else {
            onFailure?(.notReady)
            return
        }

        onWillBegin?()
        generation &+= 1
        let sessionGeneration = generation
        transcript = ""
        self.endsOnSilence = endsOnSilence
        phase = .listening

        do {
            let input = try audio.start(targetFormat: format)
            let updates = transcriber.startSession(input: input)
            sessionTask = Task { [weak self] in
                do {
                    for try await update in updates {
                        guard let self,
                              !Task.isCancelled,
                              generation == sessionGeneration
                        else { return }
                        let spoke = update.text != transcript
                        transcript = update.text
                        if spoke {
                            waitForSilence()
                        }
                    }
                } catch {
                    guard let self,
                          !Task.isCancelled,
                          generation == sessionGeneration
                    else { return }
                    audio.stop()
                    sessionTask = nil
                    transcript = ""
                    self.endsOnSilence = false
                    phase = .idle
                    onFailure?(.transcription)
                    Pipeline.log.error("Transcription stream failed: \(error, privacy: .public)")
                }
            }
        } catch {
            transcript = ""
            self.endsOnSilence = false
            phase = .idle
            onFailure?(.capture(error.localizedDescription))
            return
        }
        waitForSilence()
    }

    private func waitForSilence() {
        guard endsOnSilence else { return }
        scheduleFinish(after: silenceTail)
    }

    func scheduleFinish(after delay: Duration? = nil) {
        guard phase == .listening else { return }
        releaseTask?.cancel()
        let delay = delay ?? releaseTail
        releaseTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            releaseTask = nil
            await finish()
        }
    }

    func finish() async {
        guard phase == .listening else { return }
        let sessionGeneration = generation
        let resultTask = sessionTask
        phase = .finishing
        let trace = LatencyTrace()

        audio.stop()
        isFinalizingSession = true
        do {
            try await transcriber.finishSession()
        } catch {
            Pipeline.log.error("finishSession failed: \(error, privacy: .public)")
        }
        isFinalizingSession = false
        resumeDeferredBeginIfNeeded()
        await resultTask?.value
        guard generation == sessionGeneration, phase == .finishing else {
            trace.end()
            return
        }
        sessionTask = nil
        endsOnSilence = false
        trace.mark("finalTranscript")

        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            transcript = ""
            phase = .idle
            trace.end()
            return
        }

        if let onUtterance {
            onUtterance(text, trace)
        } else {
            trace.end()
        }
        phase = .idle
    }

    func cancel() {
        releaseTask?.cancel()
        releaseTask = nil
        beginAfterFinalization = false
        endsOnSilence = false
        let wasFinishing = phase == .finishing
        let wasListening = phase == .listening
        let wasActive = phase != .idle || sessionTask != nil
        transcript = ""
        phase = .idle
        guard wasActive else { return }

        generation &+= 1
        if wasListening {
            audio.stop()
        }
        sessionTask?.cancel()
        sessionTask = nil
        guard !wasFinishing, !isFinalizingSession else { return }
        let transcriber = transcriber
        isFinalizingSession = true
        Task { [weak self] in
            try? await transcriber.finishSession()
            guard let self else { return }
            isFinalizingSession = false
            resumeDeferredBeginIfNeeded()
        }
    }

    func clearTranscript() {
        guard phase != .listening else { return }
        transcript = ""
    }

    private func resumeDeferredBeginIfNeeded() {
        guard beginAfterFinalization, phase == .idle else { return }
        beginAfterFinalization = false
        begin(endsOnSilence: deferredEndsOnSilence)
    }
}
