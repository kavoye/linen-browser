// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct TabSessionMemory {
    private(set) var isDeferred = false
    private(set) var generation = 1
    private var deferredState: Data?
    private var deferredURL: URL?
    private var cached: Data?
    private var isFresh = false

    mutating func deferRestore(state: Data?, url: URL?) {
        guard state != nil || url != nil else { return }
        deferredState = state
        deferredURL = url
        isDeferred = true
    }

    mutating func state(isMaterialised: Bool, live: () -> Data?) -> Data? {
        if isDeferred {
            return deferredState
        }
        guard isMaterialised else {
            return cached
        }
        if !isFresh {
            cached = live()
            isFresh = true
        }
        return cached
    }

    mutating func invalidate() {
        isFresh = false
        generation &+= 1
    }

    mutating func takeDeferred() -> (state: Data?, url: URL?)? {
        guard isDeferred else { return nil }
        let deferred = (deferredState, deferredURL)
        clearDeferred()
        return deferred
    }

    mutating func clearDeferred() {
        isDeferred = false
        deferredState = nil
        deferredURL = nil
    }
}
