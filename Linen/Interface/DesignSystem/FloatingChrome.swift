// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct FloatingGround: Equatable {
    let color: NSColor?
    let isLight: Bool

    init(_ color: NSColor?, scheme: ColorScheme) {
        self.color = color
        isLight = PageInk.isLight(color, scheme: scheme)
    }

    var wash: Color {
        if let color {
            return Color(nsColor: color)
        }
        return isLight ? Color(white: 0.97) : Color(white: 0.15)
    }

    var ink: Color {
        isLight ? .black : .white
    }
}

extension EnvironmentValues {
    @Entry var floatingGround: FloatingGround?
}

struct FloatingChromeFill<S: Shape>: View {
    let shape: S
    let ground: FloatingGround

    var body: some View {
        ZStack {
            shape
                .fill(.clear)
                .glassEffect(.regular, in: shape)
            shape.fill(ground.wash.opacity(0.72))
        }
    }
}
