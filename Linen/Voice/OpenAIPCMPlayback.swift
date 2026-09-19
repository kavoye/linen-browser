// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AVFAudio
import Foundation

@MainActor
protocol StreamingSpeechPlaying: AnyObject {
    func append(_ pcm: Data) async throws
    func finish() async throws
    func stop()
}

@MainActor
protocol ConversationAudioPlaying: StreamingSpeechPlaying {
    var playedMilliseconds: Int { get }
}

@MainActor
final class OpenAIPCMPlayback: ConversationAudioPlaying {
    private let hardware: any PCMPlaybackDriving
    private var remainder = Data()
    private var pendingFrames = 0
    private var generation = 0
    private var waiting: CheckedContinuation<Void, any Error>?
    private var waitingForDrain = false
    private(set) var playedMilliseconds = 0

    init(hardware: any PCMPlaybackDriving = PCMPlaybackHardware()) {
        self.hardware = hardware
    }

    func append(_ pcm: Data) async throws {
        let generation = generation
        try Task.checkCancellation()
        if pendingFrames >= 24_000 * 10 {
            waitingForDrain = false
            try await wait()
        }
        try Task.checkCancellation()
        guard self.generation == generation else { throw CancellationError() }
        remainder.append(pcm)
        let count = remainder.count / 2
        guard count > 0 else { return }
        guard count <= 24_000 * 60 else { throw OpenAIVoiceFailure.invalidAudio }
        let bytes = Data(remainder.prefix(count * 2))
        remainder.removeFirst(count * 2)
        pendingFrames += count
        do {
            try await withTaskCancellationHandler {
                try await hardware.schedule(bytes, generation: generation, completed: { [weak self] in
                    Task { @MainActor in
                        guard let self, self.generation == generation else { return }
                        self.pendingFrames -= count
                        if self.waitingForDrain ? self.pendingFrames == 0 : self.pendingFrames < 24_000 * 10 {
                            self.waiting?.resume()
                            self.waiting = nil
                        }
                    }
                }, position: { [weak self] milliseconds in
                    Task { @MainActor in
                        guard let self, self.generation == generation else { return }
                        self.playedMilliseconds = max(self.playedMilliseconds, milliseconds)
                    }
                })
            } onCancel: {
                Task { @MainActor [weak self] in
                    guard let self, self.generation == generation else { return }
                    self.stop()
                }
            }
            try Task.checkCancellation()
            guard self.generation == generation else { throw CancellationError() }
        } catch {
            if self.generation == generation {
                stop()
            }
            throw error
        }
    }

    func finish() async throws {
        guard remainder.isEmpty else { throw OpenAIVoiceFailure.invalidAudio }
        if pendingFrames > 0 {
            waitingForDrain = true
            try await wait()
        }
        try Task.checkCancellation()
    }

    private func wait() async throws {
        let generation = generation
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { waiting = $0 }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                self.stop()
            }
        }
    }

    func stop() {
        generation &+= 1
        hardware.stop(generation: generation)
        pendingFrames = 0
        playedMilliseconds = 0
        remainder.removeAll()
        waiting?.resume(throwing: CancellationError())
        waiting = nil
    }
}

nonisolated protocol PCMPlaybackDriving: Sendable {
    func schedule(_ pcm: Data, generation: Int, completed: @escaping @Sendable () -> Void,
                  position: @escaping @Sendable (Int) -> Void) async throws
    func stop(generation: Int)
}

nonisolated final class PCMPlaybackHardware: PCMPlaybackDriving, @unchecked Sendable {
    private static let queue = DispatchQueue(label: "com.kavoye.linen.audio-playback", qos: .default)
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var timeline = OpenAIPlaybackTimeline()
    private var timer: DispatchSourceTimer?
    private var scheduledBuffers = 0
    private var generation = 0

    func schedule(_ pcm: Data, generation: Int, completed: @escaping @Sendable () -> Void,
                  position: @escaping @Sendable (Int) -> Void) async throws {
        try await withCheckedThrowingContinuation { (result: CheckedContinuation<Void, any Error>) in
            Self.queue.async {
                guard self.generation == generation else {
                    result.resume(throwing: CancellationError())
                    return
                }
                do {
                    try self.enqueue(pcm, completed: completed, position: position)
                    result.resume()
                } catch {
                    self.close()
                    result.resume(throwing: error)
                }
            }
        }
    }

    private func enqueue(_ pcm: Data, completed: @escaping @Sendable () -> Void,
                         position: @escaping @Sendable (Int) -> Void) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
        let count = pcm.count / 2
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
              let samples = buffer.floatChannelData?[0] else { throw OpenAIVoiceFailure.invalidAudio }
        buffer.frameLength = AVAudioFrameCount(count)
        for index in 0..<count {
            let offset = pcm.startIndex + index * 2
            let bits = UInt16(pcm[offset]) | (UInt16(pcm[offset + 1]) << 8)
            samples[index] = Float(Int16(bitPattern: bits)) / 32_768
        }
        if engine == nil {
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            self.engine = engine
            self.player = player
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            try engine.start()
        }
        guard let player else { throw OpenAIVoiceFailure.invalidAudio }
        let start = timeline.schedule(frames: count, renderedFrame: renderedFrame)
        let generation = generation
        scheduledBuffers += 1
        player.scheduleBuffer(buffer, at: AVAudioTime(sampleTime: start, atRate: 24_000), completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Self.queue.async { [weak self] in
                guard let self, self.generation == generation else { return }
                self.timeline.complete(start: start)
                self.reportPosition(position)
                self.scheduledBuffers -= 1
                if self.scheduledBuffers == 0 {
                    self.timer?.cancel()
                    self.timer = nil
                }
                completed()
            }
        }
        if !player.isPlaying {
            player.play()
        }
        if timer == nil {
            let timer = DispatchSource.makeTimerSource(queue: Self.queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(50), leeway: .milliseconds(10))
            timer.setEventHandler { [weak self] in self?.reportPosition(position) }
            self.timer = timer
            timer.resume()
        }
    }

    private var renderedFrame: Int64 {
        guard let player, let render = player.lastRenderTime,
              let time = player.playerTime(forNodeTime: render) else { return 0 }
        return time.sampleTime
    }

    private func reportPosition(_ position: @Sendable (Int) -> Void) {
        position(timeline.playedMilliseconds(renderedFrame: renderedFrame, latency: player?.outputPresentationLatency ?? 0))
    }

    func stop(generation: Int) {
        Self.queue.async {
            self.close()
            self.generation = generation
        }
    }

    private func close() {
        generation &+= 1
        timer?.cancel()
        timer = nil
        scheduledBuffers = 0
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        timeline = OpenAIPlaybackTimeline()
    }

    deinit {
        timer?.cancel()
        let player = player
        let engine = engine
        Self.queue.async {
            player?.stop()
            engine?.stop()
        }
    }
}

nonisolated struct OpenAIPlaybackTimeline {
    private struct Segment {
        let start: Int64
        let frames: Int64
    }
    private var segments: [Segment] = []
    private var nextFrame: Int64 = 0
    private var completedFrames: Int64 = 0

    mutating func schedule(frames: Int, renderedFrame: Int64) -> Int64 {
        let start = max(nextFrame, max(0, renderedFrame))
        segments.append(.init(start: start, frames: Int64(frames)))
        nextFrame = start + Int64(frames)
        return start
    }

    mutating func complete(start: Int64) {
        guard let index = segments.firstIndex(where: { $0.start == start }) else { return }
        completedFrames += segments.remove(at: index).frames
    }

    func playedMilliseconds(renderedFrame: Int64, latency: Double) -> Int {
        guard latency.isFinite, (0...60).contains(latency) else { return Int(completedFrames * 1_000 / 24_000) }
        let audibleFrame = max(0, renderedFrame - Int64((latency * 24_000).rounded(.up)))
        let played = segments.reduce(completedFrames) { frames, segment in
            frames + min(segment.frames, max(0, audibleFrame - segment.start))
        }
        return Int(played * 1_000 / 24_000)
    }
}
