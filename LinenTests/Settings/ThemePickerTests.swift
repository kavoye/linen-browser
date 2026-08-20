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
}
