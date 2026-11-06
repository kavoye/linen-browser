// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct LinkWindowMenuItems: View {
    let isPrivate: Bool
    let onOpen: (_ isPrivate: Bool) -> Void

    var body: some View {
        if isPrivate {
            privateWindow
        } else {
            Button("Open Link in New Window", systemImage: "macwindow.badge.plus") { onOpen(false) }
                .modifierKeyAlternate(.option) {
                    privateWindow
                }
        }
    }

    private var privateWindow: some View {
        Button("Open Link in New Private Window", systemImage: "hand.raised") { onOpen(true) }
    }
}
