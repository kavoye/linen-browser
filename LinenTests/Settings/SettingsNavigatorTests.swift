// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SwiftUI
import Testing

@testable import Linen

struct SettingsNavigatorTests {
    @Test func categoryRawValuesAreStable() {
        let expected = [
            "general", "search", "appearance", "provider", "voice", "profiles",
            "privacy", "websites", "downloads", "extensions", "advanced", "about",
        ]
        #expect(SettingsCategory.allCases.map(\.rawValue) == expected)
    }

    @Test func theProviderPageIsTitledAssistant() {
        #expect(String(localized: SettingsCategory.provider.title) == "Assistant")
        #expect(SettingsCategory.provider.id == "provider")
    }

    @Test func profilesIsReachedFromTheProfileBlockNotAGroup() {
        #expect(SettingsCategory.profiles.group == nil)
        for group in SettingsGroup.allCases {
            #expect(!group.categories.contains(.profiles))
        }
    }

    @Test func everyOtherCategoryBelongsToExactlyOneGroup() {
        let grouped = SettingsGroup.allCases.flatMap(\.categories)
        #expect(Set(grouped).count == grouped.count)
        #expect(Set(grouped) == Set(SettingsCategory.allCases).subtracting([.profiles]))
    }

    @Test func theFirstGroupIsUnheaded() {
        #expect(SettingsGroup.setup.header == nil)
    }

    @Test func theHeadedGroupsReadAsChosen() {
        let headers = SettingsGroup.allCases
            .compactMap(\.header)
            .map { String(localized: $0) }
        #expect(headers == ["Browsing", "System"])
    }

    @Test func noGroupHeaderRepeatsACategoryInsideIt() {
        for group in SettingsGroup.allCases {
            guard let header = group.header else { continue }
            let titles = group.categories.map { String(localized: $0.title) }
            #expect(!titles.contains(String(localized: header)), "\(titles)")
        }
    }

    @Test func everyCategoryCarriesATileTint() {
        for category in SettingsCategory.allCases {
            #expect(category.tint != .clear)
        }
    }

    @Test func profilesIsStillFoundBySearch() {
        #expect(SettingsCategory.profiles.matches("profiles"))
        #expect(SettingsCategory.profiles.matches("work"))
        #expect(!SettingsCategory.profiles.matches("javascript"))
    }

    @Test func theOldProviderNameStillFindsThePage() {
        #expect(SettingsCategory.provider.matches("provider"))
    }
}
