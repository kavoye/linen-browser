// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct UnloadedTabBadge: View {
    var size: CGFloat = 9.5

    var body: some View {
        let help = Text("Unloaded to save memory. It reloads when selected.")
        Image(systemName: "moon.zzz.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(.secondary)
            .help(help)
            .accessibilityLabel(help)
    }
}
