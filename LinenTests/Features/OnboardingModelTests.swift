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
        #expect(model.step == .extensions)
        model.advance()
        #expect(model.step == .bookmarks)
        model.advance()
        #expect(model.step == .finish)
        #expect(model.isLastStep)
        model.advance()
        #expect(!model.isPresented)

        let reopened = OnboardingModel(defaults: defaults)
        reopened.beginIfNeeded()
        #expect(!reopened.isPresented)
    }

    @Test func goingBackWalksToTheFirstStepAndStops() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = OnboardingModel(defaults: defaults)

        model.beginIfNeeded()
        for _ in OnboardingModel.Step.allCases.dropLast() {
            model.advance()
        }
        #expect(model.step == .finish)

        model.back()
        #expect(model.step == .bookmarks)
        model.back()
        #expect(model.step == .extensions)
        model.back()
        model.back()
        #expect(model.step == .welcome)

        model.back()
        #expect(model.step == .welcome)
        #expect(model.isPresented)
    }

    @Test func onlyTheMiddleStepsCarryNavigation() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = OnboardingModel(defaults: defaults)

        model.beginIfNeeded()
        #expect(!model.showsNavigation)
        model.advance()
        #expect(model.showsNavigation)
        model.advance()
        #expect(model.showsNavigation)
        model.advance()
        #expect(model.showsNavigation)
        model.advance()
        #expect(!model.showsNavigation)
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
