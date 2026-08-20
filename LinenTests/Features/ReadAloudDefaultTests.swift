// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Testing

@testable import Linen

struct ReadAloudDefaultTests {
    /// A fresh install says nothing out loud until asked to.
    @Test func aFreshInstallStartsMuted() {
        #expect(AppCoordinator.initialSpeechMuted(stored: nil))
    }

    /// The default changed, not anyone's choice: a stored value wins in both
    /// directions.
    @Test func anExplicitChoiceSurvivesTheNewDefault() {
        #expect(AppCoordinator.initialSpeechMuted(stored: false) == false)
        #expect(AppCoordinator.initialSpeechMuted(stored: true) == true)
    }
}
