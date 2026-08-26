// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// Extensions take an update once a day, quietly. The sweep decides whether
/// today's has already happened, and that decision is what keeps a launch
/// from reaching the store every time.
@MainActor
struct ExtensionUpdateTests {
    private let key = "extensions.lastUpdateCheck"

    private func scratchDefaults() -> UserDefaults {
        let suite = "com.kavoye.Linen.tests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite) ?? .standard
    }

    private func manager(_ defaults: UserDefaults) -> ExtensionManager {
        ExtensionManager.defaults = defaults
        return ExtensionManager(browser: BrowserModel(database: .temporary()))
    }

    @Test func theFirstLaunchOfTheDayTakesTheSweep() async {
        let defaults = scratchDefaults()
        defer { ExtensionManager.defaults = .standard }
        let extensions = manager(defaults)

        await extensions.updateInstalledIfDue()

        #expect(defaults.object(forKey: key) is Date, "the sweep records when it ran")
    }

    @Test func aSweepAnHourOldIsNotDueAgain() async {
        let defaults = scratchDefaults()
        defer { ExtensionManager.defaults = .standard }
        let anHourAgo = Date().addingTimeInterval(-3_600)
        defaults.set(anHourAgo, forKey: key)
        let extensions = manager(defaults)

        await extensions.updateInstalledIfDue()

        #expect(defaults.object(forKey: key) as? Date == anHourAgo, "the stamp is left where it was")
    }

    @Test func aSweepFromYesterdayIsDue() async {
        let defaults = scratchDefaults()
        defer { ExtensionManager.defaults = .standard }
        let yesterday = Date().addingTimeInterval(-90_000)
        defaults.set(yesterday, forKey: key)
        let extensions = manager(defaults)

        await extensions.updateInstalledIfDue()

        let stamped = defaults.object(forKey: key) as? Date
        #expect(stamped != nil)
        #expect((stamped ?? .distantPast) > yesterday, "a day later the sweep runs again")
    }

    /// The caller passes the clock in, so a machine that has been asleep for
    /// a week is the same test as one that has not.
    @Test func theSweepJudgesTheClockItIsGiven() async {
        let defaults = scratchDefaults()
        defer { ExtensionManager.defaults = .standard }
        let now = Date()
        defaults.set(now, forKey: key)
        let extensions = manager(defaults)

        await extensions.updateInstalledIfDue(now: now.addingTimeInterval(60))
        #expect(defaults.object(forKey: key) as? Date == now)

        await extensions.updateInstalledIfDue(now: now.addingTimeInterval(86_401))
        #expect(defaults.object(forKey: key) as? Date != now)
    }

    @Test func anExtensionThatIsNotInstalledIsNotChecked() async {
        let defaults = scratchDefaults()
        defer { ExtensionManager.defaults = .standard }
        let extensions = manager(defaults)

        await extensions.checkForUpdate(id: "not-installed")

        #expect(extensions.updateChecks["not-installed"] == nil, "nothing to report about nothing")
    }
}
