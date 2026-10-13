// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct UnloadedTabBadge: View {
    var size: CGFloat = 9.5

    private static let ink = Theme.adaptive(
        dark: NSColor(white: 0.72, alpha: 1),
        light: NSColor(white: 0.42, alpha: 1)
    )

    var body: some View {
        let help = Text("Unloaded to save memory. It reloads when selected.")
        Image(systemName: "moon.zzz.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Self.ink)
            .help(help)
            .accessibilityLabel(help)
    }
}
