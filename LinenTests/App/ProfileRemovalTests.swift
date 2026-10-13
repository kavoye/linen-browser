// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@MainActor
@Suite(.serialized)
struct ProfileRemovalTests {
    private func watches() -> PageWatchCenter {
        PageWatchCenter(
            file: nil,
            schedules: true,
            fetch: { _ in PageWatchReading(title: "Kettle", text: "Kettle $54.99 In stock") },
            judge: { _, _ in PageWatchVerdict(met: false, state: "$54.99", message: "") },
            classify: { _, _ in nil },
            notify: { _, _ in }
        )
    }

    @Test func removingAProfileStopsItsPageWatchesFirst() async throws {
        let work = Profile(id: UUID(), name: "Work", symbol: "briefcase", color: .gray)
        let context = BrowserProfileContext.shared(for: work)
        defer { BrowserProfileContext.forget(work.id) }
        let center = watches()
        context.pageWatches = center
        center.resume()
        #expect(center.isScheduling)

        await BrowserApplication().prepareToRemove(profile: work)

        #expect(!center.isScheduling)
    }

    @Test func theOriginalProfileIsNeverRemoved() async {
        let original = Profile.original()
        let context = BrowserProfileContext.shared(for: original)
        let previous = context.pageWatches
        let center = watches()
        context.pageWatches = center
        defer {
            context.pageWatches = previous
        }
        center.resume()

        await BrowserApplication().prepareToRemove(profile: original)

        #expect(center.isScheduling)
        await center.close()
    }
}
