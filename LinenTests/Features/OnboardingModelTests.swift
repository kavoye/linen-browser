// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@MainActor
struct OnboardingModelTests {
    @Test func setupAdvancesOnceAndStaysCompleted() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = OnboardingModel(defaults: defaults)

        #expect(!model.isPresented)
        model.beginIfNeeded()
        #expect(model.step == .welcome)

        model.advance()
        #expect(model.step == .model)
        model.advance()
        #expect(model.step == .history)
        #expect(model.isLastStep)
        model.advance()
        #expect(!model.isPresented)

        let reopened = OnboardingModel(defaults: defaults)
        reopened.beginIfNeeded()
        #expect(!reopened.isPresented)
    }

    @Test func finishingBeforeSetupDoesNotMarkItComplete() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = OnboardingModel(defaults: defaults)

        model.finish()
        model.beginIfNeeded()

        #expect(model.step == .welcome)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "Linen.OnboardingModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }
}
