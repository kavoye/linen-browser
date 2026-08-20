// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Testing

actor WebViewGate {
    static let shared = WebViewGate(limit: 2)

    private let limit: Int
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    func acquire() async {
        guard active >= limit else {
            active += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
        if waiting.isEmpty {
            active -= 1
        } else {
            waiting.removeFirst().resume()
        }
    }
}

nonisolated struct BoundedWebViews: TestTrait, SuiteTrait, TestScoping {
    var isRecursive: Bool {
        true
    }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
        guard testCase != nil else {
            try await function()
            return
        }
        await WebViewGate.shared.acquire()
        do {
            try await function()
        } catch {
            await WebViewGate.shared.release()
            throw error
        }
        await WebViewGate.shared.release()
    }
}

extension Trait where Self == BoundedWebViews {
    static var boundedWebViews: Self {
        Self()
    }
}
