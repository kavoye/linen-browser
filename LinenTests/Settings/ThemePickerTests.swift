// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

struct ThemePickerTests {
    @Test func everyModeHasSomethingToDraw() {
        for mode in AppearanceMode.allCases {
            #expect(!ThemeThumbnailPalette.palettes(for: mode).isEmpty)
        }
    }

    @Test func aFixedModeIsDrawnInOnePalette() {
        #expect(ThemeThumbnailPalette.palettes(for: .light) == [.light])
        #expect(ThemeThumbnailPalette.palettes(for: .dark) == [.dark])
    }

    @Test func systemIsDrawnInBothPalettes() {
        #expect(ThemeThumbnailPalette.palettes(for: .system) == [.light, .dark])
    }

    @Test func theLightAndDarkPalettesAreDifferent() {
        #expect(ThemeThumbnailPalette.light != ThemeThumbnailPalette.dark)
    }

    @Test func choosingAModePersistsIt() throws {
        let suite = try #require(UserDefaults(suiteName: "ThemePickerTests.\(UUID().uuidString)"))
        defer { suite.removePersistentDomain(forName: suite.description) }

        let settings = BrowserSettings(defaults: suite)
        for mode in AppearanceMode.allCases {
            settings.appearance = mode
            #expect(BrowserSettings(defaults: suite).appearance == mode)
        }
    }

    @Test func windowStyleDefaultsToStandardAndPersists() throws {
        let suite = try #require(UserDefaults(suiteName: "WebsiteColorTests.\(UUID().uuidString)"))
        defer { suite.removePersistentDomain(forName: suite.description) }

        #expect(BrowserSettings(defaults: suite).loomStyle == .standard)
        BrowserSettings(defaults: suite).loomStyle = .transparent
        #expect(BrowserSettings(defaults: suite).loomStyle == .transparent)
    }

    @Test func websiteTintPersistsIndependentlyOfWindowStyle() throws {
        let suite = try #require(UserDefaults(suiteName: "WebsiteTintTests.\(UUID().uuidString)"))
        defer { suite.removePersistentDomain(forName: suite.description) }

        let settings = BrowserSettings(defaults: suite)
        settings.loomStyle = .transparent
        settings.matchesWebsiteColor = true

        let restored = BrowserSettings(defaults: suite)
        #expect(restored.loomStyle == .transparent)
        #expect(restored.matchesWebsiteColor)
    }

    @Test func legacyWebsiteTintStyleMigratesToStandardWithTintEnabled() throws {
        let suite = try #require(UserDefaults(suiteName: "WebsiteTintMigrationTests.\(UUID().uuidString)"))
        defer { suite.removePersistentDomain(forName: suite.description) }
        suite.set("websiteTint", forKey: "appearance.loomStyle")

        let settings = BrowserSettings(defaults: suite)
        #expect(settings.loomStyle == .standard)
        #expect(settings.matchesWebsiteColor)
    }
}
