// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

@MainActor
final class TabArchiveSweeper {
    var onSweep: (() -> Void)?

    private let interval: Duration
    private var task: Task<Void, Never>?

    init(interval: Duration = .seconds(10 * 60)) {
        self.interval = interval
    }

    func start() {
        guard task == nil else { return }
        let interval = interval
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.onSweep?()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
