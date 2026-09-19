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
