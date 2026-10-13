// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@MainActor
struct ModelActivityTests {
    @Test func runsOnlyWhileWorkIsInFlight() async {
        let activity = ModelActivity()
        let gate = AsyncStream<Void>.makeStream()
        #expect(!activity.isRunning)

        let pending = Task { await activity.perform { for await _ in gate.stream {}; return 7 } }
        #expect(await waitUntil { activity.isRunning })

        gate.continuation.finish()
        #expect(await pending.value == 7)
        #expect(!activity.isRunning)
    }

    @Test func cancelAllEndsTheWorkWithoutAResult() async {
        let activity = ModelActivity()
        let pending = Task {
            await activity.perform { () -> Int in
                try? await Task.sleep(for: .seconds(60))
                return 7
            }
        }
        #expect(await waitUntil { activity.isRunning })

        activity.cancelAll()
        #expect(await pending.value == nil)
        #expect(!activity.isRunning)
    }

    @Test func stoppingTheAgentStopsDirectModelWork() async {
        let coordinator = AppCoordinator()
        let activity = coordinator.browser.modelActivity
        let pending = Task {
            await activity.perform { () -> Int in
                try? await Task.sleep(for: .seconds(60))
                return 7
            }
        }
        #expect(await waitUntil { activity.isRunning })

        coordinator.stopAgent()
        #expect(await pending.value == nil)
        #expect(!activity.isRunning)
    }
}
