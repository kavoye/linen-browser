// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Dispatch
import Foundation

@MainActor
final class MemoryPressureMonitor {
    enum Level: Sendable {
        case warning
        case critical
    }

    var onPressure: ((Level) -> Void)?

    private var source: (any DispatchSourceMemoryPressure)?

    func start() {
        guard source == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let data = self.source?.data else { return }
                self.onPressure?(data.contains(.critical) ? .critical : .warning)
            }
        }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    deinit {
        source?.cancel()
    }
}
