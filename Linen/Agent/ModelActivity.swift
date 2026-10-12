// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

@MainActor
@Observable
final class ModelActivity {
    private var running: [UUID: () -> Void] = [:]

    var isRunning: Bool {
        !running.isEmpty
    }

    func perform<T: Sendable>(_ work: @escaping @MainActor () async -> T) async -> T? {
        let id = UUID()
        let task = Task { await work() }
        running[id] = { task.cancel() }
        defer { running[id] = nil }
        let value = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        return task.isCancelled ? nil : value
    }

    func cancelAll() {
        for cancel in running.values {
            cancel()
        }
    }
}
