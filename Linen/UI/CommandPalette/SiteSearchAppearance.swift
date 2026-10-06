// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct SiteSearchAppearance {
    let background: Color
    let foreground: Color

    init(site: SearchEngine) {
        // Custom engines using a known site's host share its chip color.
        let identifier = SiteSearch.catalog.first { $0.host == site.host }?.id ?? site.id
        switch identifier {
        case "youtube":
            self.init(rgb: 0xFF0033)
        case "reddit":
            self.init(rgb: 0xFF4500, foreground: .black)
        case "github":
            self.init(rgb: 0x24292F)
        case "amazon":
            self.init(rgb: 0xFF9900, foreground: .black)
        case "duckduckgo":
            self.init(rgb: 0xDE5833, foreground: .black)
        case "google":
            self.init(rgb: 0x4285F4, foreground: .black)
        case "bing":
            self.init(rgb: 0x008373)
        case "brave":
            self.init(rgb: 0xFB542B, foreground: .black)
        case "startpage":
            self.init(rgb: 0x6573FF, foreground: .black)
        case "ecosia":
            self.init(rgb: 0x008009)
        case "kagi":
            self.init(rgb: 0xFFB319, foreground: .black)
        case "wikipedia":
            self.init(rgb: 0xEAECF0, foreground: .black)
        default:
            self.init(rgb: 0x55565C)
        }
    }

    private init(rgb: UInt32, foreground: Color = .white) {
        background = Color(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: 1
        )
        self.foreground = foreground
    }
}
