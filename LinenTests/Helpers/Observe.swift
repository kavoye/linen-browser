// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Observation

@MainActor
func waitForObservation(_ condition: @escaping @MainActor () -> Bool) async -> Bool {
    let (changes, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    defer { continuation.finish() }
    var iterator = changes.makeAsyncIterator()
    while !Task.isCancelled {
        let satisfied = withObservationTracking {
            condition()
        } onChange: {
            continuation.yield(())
        }
        if satisfied {
            return true
        }
        guard await iterator.next() != nil else { return false }
    }
    return false
}
