// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Synchronization

nonisolated final class TestClock: Clock, Sendable {
    typealias Instant = ContinuousClock.Instant

    private struct Waiter {
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = ContinuousClock.now
        var waiters: [UUID: Waiter] = [:]
    }

    private let state = Mutex(State())

    var now: Instant {
        state.withLock { $0.now }
    }
    var minimumResolution: Duration {
        .nanoseconds(1)
    }
    var pendingCount: Int {
        state.withLock { $0.waiters.count }
    }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                state.withLock { state in
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else if deadline <= state.now {
                        continuation.resume()
                    } else {
                        state.waiters[id] = Waiter(deadline: deadline, continuation: continuation)
                    }
                }
            }
        } onCancel: {
            let waiter = self.state.withLock { $0.waiters.removeValue(forKey: id) }
            waiter?.continuation.resume(throwing: CancellationError())
        }
    }

    func advance(by duration: Duration) {
        precondition(duration >= .zero)
        let ready = state.withLock { state in
            state.now += duration
            let ready = state.waiters.filter { $0.value.deadline <= state.now }
            for id in ready.keys {
                state.waiters[id] = nil
            }
            return Array(ready.values)
        }
        for waiter in ready {
            waiter.continuation.resume()
        }
    }
}
