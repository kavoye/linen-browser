// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

@MainActor
@Observable
final class TimedStatus {
    var message: String? {
        didSet {
            fade?.cancel()
            fade = nil
            guard message != nil else { return }
            fade = Task { [weak self, lifetime] in
                try? await Task.sleep(for: lifetime)
                guard !Task.isCancelled else { return }
                self?.message = nil
            }
        }
    }

    @ObservationIgnored private let lifetime: Duration
    @ObservationIgnored private var fade: Task<Void, Never>?

    init(lifetime: Duration) {
        self.lifetime = lifetime
    }
}
