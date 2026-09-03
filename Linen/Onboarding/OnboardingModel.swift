// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

@MainActor
@Observable
final class OnboardingModel {
    enum Step: Int, CaseIterable {
        case welcome
        case model
        case extensions
        case bookmarks
        case finish
    }

    enum ModelChoice {
        case onDevice
        case remote
    }

    private static let completedKey = "onboarding.completed"

    private let defaults: UserDefaults

    private(set) var step: Step?

    var modelChoice: ModelChoice = .onDevice

    private(set) var handedOverToSystemSettings = false

    private(set) var hasPlayedIntro = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isPresented: Bool {
        step != nil
    }

    var isLastStep: Bool {
        step == Step.allCases.last
    }

    var showsNavigation: Bool {
        guard let step else { return false }
        return step != .welcome && step != .finish
    }

    func beginIfNeeded() {
        guard !defaults.bool(forKey: Self.completedKey), step == nil else { return }
        step = .welcome
    }

    func advance() {
        guard let step else { return }
        if let next = Step(rawValue: step.rawValue + 1) {
            self.step = next
        } else {
            finish()
        }
    }

    func back() {
        guard let step, let previous = Step(rawValue: step.rawValue - 1) else { return }
        self.step = previous
    }

    func markIntroPlayed() {
        hasPlayedIntro = true
    }

    func finish() {
        guard step != nil else { return }
        defaults.set(true, forKey: Self.completedKey)
        step = nil
    }

    func requestDefaultBrowser() {
        Task {
            handedOverToSystemSettings = await DefaultBrowser.request() == .handedOverToSystemSettings
        }
    }
}
