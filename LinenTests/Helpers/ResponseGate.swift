// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Synchronization

nonisolated final class ResponseGate: Sendable {
    private struct State {
        var isOpen = false
        var requestCount = 0
        var pending: [@Sendable () -> Void] = []
    }

    private let state = Mutex(State())
    private let requests = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))

    func waitForRequest() async -> Bool {
        if requestCount > 0 {
            return true
        }
        for await _ in requests.stream {
            return true
        }
        return false
    }

    var requestCount: Int { state.withLock {
        $0.requestCount }
    }

    func submit(_ response: @escaping @Sendable () -> Void) {
        let sendNow = state.withLock { state in
            state.requestCount += 1
            guard !state.isOpen else { return true }
            state.pending.append(response)
            return false
        }
        requests.continuation.yield(())
        if sendNow {
            response()
        }
    }

    func open() {
        let pending = state.withLock { state in
            state.isOpen = true
            let pending = state.pending
            state.pending = []
            return pending
        }
        for response in pending {
            response()
        }
    }
}
