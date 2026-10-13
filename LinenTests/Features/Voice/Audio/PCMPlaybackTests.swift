// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Synchronization
import Testing

@testable import Linen

@MainActor
struct PCMPlaybackTests {
    @Test func stoppingWhileSchedulingRejectsLateStartupAndCallbacks() async throws {
        let hardware = PlaybackHardwareFixture()
        let playback = OpenAIPCMPlayback(hardware: hardware)
        let append = Task { try await playback.append(Data([0, 0])) }
        defer { hardware.gate.open(); playback.stop() }
        try #require(await waitUntil { hardware.calls.count == 1 })
        playback.stop()
        #expect(hardware.stops == [1])
        hardware.gate.open()
        await #expect(throws: CancellationError.self) { try await append.value }
        try await playback.append(Data([0, 0]))
        let calls = hardware.calls
        #expect(calls.map(\.generation) == [0, 1])
        calls[0].position(900)
        calls[0].completed()
        calls[1].position(50)
        try #require(await waitUntil { playback.playedMilliseconds == 50 })
        calls[1].completed()
        try await playback.finish()
        #expect(playback.playedMilliseconds == 50)
    }

    @Test func cancellationStopsPendingHardwareWithoutBlockingTheMainActor() async throws {
        let hardware = PlaybackHardwareFixture()
        let playback = OpenAIPCMPlayback(hardware: hardware)
        let append = Task { try await playback.append(Data([0, 0])) }
        defer { hardware.gate.open(); playback.stop() }
        try #require(await waitUntil { hardware.calls.count == 1 })
        append.cancel()
        try #require(await waitUntil { hardware.stops == [1] })
        hardware.gate.open()
        await #expect(throws: CancellationError.self) { try await append.value }
        #expect(playback.playedMilliseconds == 0)
    }

    @Test func splitSamplesAndDrainCancellationKeepTheNextReplyUsable() async throws {
        let hardware = PlaybackHardwareFixture()
        hardware.gate.open()
        let playback = OpenAIPCMPlayback(hardware: hardware)
        defer { playback.stop() }
        try await playback.append(Data([12]))
        #expect(hardware.calls.isEmpty)
        try await playback.append(Data([34]))
        #expect(hardware.calls.first?.bytes == Data([12, 34]))
        let finish = Task { try await playback.finish() }
        await Task.yield()
        finish.cancel()
        await #expect(throws: CancellationError.self) { try await finish.value }
        try #require(await waitUntil { !hardware.stops.isEmpty })
        try await playback.append(Data([56, 78]))
        hardware.calls.last?.completed()
        try await playback.finish()
    }
}

private nonisolated final class PlaybackHardwareFixture: PCMPlaybackDriving, Sendable {
    struct Call: Sendable {
        let generation: Int
        let bytes: Data
        let completed: @Sendable () -> Void
        let position: @Sendable (Int) -> Void
    }
    private struct State {
        var calls: [Call] = []
        var stops: [Int] = []
    }
    private let state = Mutex(State())
    let gate = ResponseGate()
    var calls: [Call] {
        state.withLock { $0.calls }
    }
    var stops: [Int] {
        state.withLock { $0.stops }
    }

    func schedule(_ pcm: Data, generation: Int, completed: @escaping @Sendable () -> Void,
                  position: @escaping @Sendable (Int) -> Void) async throws {
        state.withLock { $0.calls.append(.init(generation: generation, bytes: pcm, completed: completed, position: position)) }
        await withCheckedContinuation { result in
            gate.submit { result.resume() }
        }
    }

    func stop(generation: Int) {
        state.withLock { $0.stops.append(generation) }
    }
}
