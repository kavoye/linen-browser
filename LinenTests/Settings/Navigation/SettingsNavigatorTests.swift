// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SwiftUI
import Testing

@testable import Linen

struct SettingsNavigatorTests {
    @Test func categoryRawValuesAreStable() {
        let expected = [
            "general", "appearance", "search", "provider", "voice",
            "privacy", "autofill", "websites", "downloads", "extensions", "advanced", "experiments", "about",
        ]
        #expect(SettingsCategory.allCases.map(\.rawValue) == expected)
    }

    @Test func theProviderPageIsTitledAssistant() {
        #expect(String(localized: SettingsCategory.provider.title) == "Assistant")
        #expect(SettingsCategory.provider.id == "provider")
    }

    @Test func everyCategoryBelongsToExactlyOneGroup() {
        let grouped = SettingsGroup.allCases.flatMap(\.categories)
        #expect(Set(grouped).count == grouped.count)
        #expect(Set(grouped) == Set(SettingsCategory.allCases))
    }

    @Test func everyCategoryCarriesATileTint() {
        for category in SettingsCategory.allCases {
            #expect(category.tint != .clear)
        }
    }

    @Test func theOldProviderNameStillFindsThePage() {
        #expect(SettingsCategory.provider.matches("provider"))
    }

    @Test func voiceTopicsFindTheVoicePage() {
        #expect(SettingsCategory.voice.matches("voice"))
        #expect(SettingsCategory.voice.matches("microphone"))
        #expect(SettingsCategory.voice.matches("push to talk"))
        #expect(SettingsCategory.voice.group == .intelligence)
    }
}
