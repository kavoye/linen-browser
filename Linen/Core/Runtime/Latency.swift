// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

nonisolated enum Pipeline {
    static let log = Logger(subsystem: "com.kavoye.Linen", category: "pipeline")
    static let signposter = OSSignposter(subsystem: "com.kavoye.Linen", category: "pipeline")
}

struct LatencyTrace {
    private let start = ContinuousClock.now
    private let signpostID: OSSignpostID
    private let signpostState: OSSignpostIntervalState

    init() {
        signpostID = Pipeline.signposter.makeSignpostID()
        signpostState = Pipeline.signposter.beginInterval("utterance", id: signpostID)
    }

    func mark(_ label: StaticString) {
        let ms = (ContinuousClock.now - start).milliseconds
        Pipeline.signposter.emitEvent(label, id: signpostID)
        Pipeline.log.info("⏱ \(label, privacy: .public): \(ms) ms")
    }

    func end() {
        Pipeline.signposter.endInterval("utterance", signpostState)
    }
}

extension Duration {
    var milliseconds: Int64 {
        components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000
    }
}
