// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

@MainActor
@Observable
final class OnboardingModel {
    enum Step: Int, CaseIterable {
        case welcome
        case style
        case extensions
        case bookmarks
        case finish
    }

    private static let completedKey = "onboarding.completed"

    private let defaults: UserDefaults

    private(set) var step: Step?

    var prefersMinimal: Bool?

    private(set) var isHandingOff = false

    private(set) var isRevealing = false

    private(set) var handedOverToSystemSettings = false

    private(set) var hasPlayedIntro = false

    private(set) var isWindowReady = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func markWindowReady() {
        isWindowReady = true
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

    func beginHandOff() {
        guard step != nil else { return }
        isHandingOff = true
    }

    func beginReveal() {
        guard isHandingOff else { return }
        isRevealing = true
    }

    func finish() {
        guard step != nil else { return }
        defaults.set(true, forKey: Self.completedKey)
        step = nil
        isHandingOff = false
        isRevealing = false
    }

    func requestDefaultBrowser() {
        Task {
            handedOverToSystemSettings = await DefaultBrowser.request() == .handedOverToSystemSettings
        }
    }
}
