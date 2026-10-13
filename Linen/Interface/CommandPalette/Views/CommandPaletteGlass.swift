// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct CommandPaletteGlass: View {
    let referenceHeight: CGFloat

    @Environment(\.paletteIsLeaving) private var isLeaving
    @Environment(\.floatingGround) private var floatingGround

    var body: some View {
        // Liquid Glass thins out on short views. Keep its rendering area at the expanded
        // palette size, then crop it to the current bounds without adding another material.
        ZStack {
            GeometryReader { geometry in
                Color.clear
                    .frame(width: geometry.size.width, height: max(referenceHeight, geometry.size.height))
                    .glassEffect(isLeaving ? .identity : .regular, in: .rect(cornerRadius: Theme.Radius.panel, style: .continuous))
            }
            if let floatingGround {
                floatingGround.wash.opacity(isLeaving ? 0 : 0.72)
            }
        }
        .clipShape(.rect(cornerRadius: Theme.Radius.panel, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
