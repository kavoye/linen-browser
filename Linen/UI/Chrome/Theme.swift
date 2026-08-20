// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

enum Theme {
    static let windowBackground = adaptive(
        dark: NSColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1),
        light: NSColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1)
    )

    static let sidebarTint = adaptive(
        dark: NSColor(red: 0.05, green: 0.05, blue: 0.065, alpha: 1),
        light: NSColor(red: 0.91, green: 0.91, blue: 0.93, alpha: 1)
    )

    static let accent = Color.blue
    static let danger = Color(nsColor: .systemRed)
    static let success = Color(nsColor: .systemGreen)

    static let warning = adaptive(
        dark: NSColor(red: 0.90, green: 0.64, blue: 0.39, alpha: 1),
        light: NSColor(red: 0.71, green: 0.33, blue: 0.05, alpha: 1)
    )

    enum Radius {
        static var window: CGFloat {
            SystemWindowShape.cornerRadius
        }
        static let panel: CGFloat = 20
        static let card: CGFloat = 14
        static let control: CGFloat = 10
        static let chip: CGFloat = 6
        static let tight: CGFloat = 4

        static func nested(in container: CGFloat, inset: CGFloat) -> CGFloat {
            max(tight, container - inset)
        }

        static let hover: CGFloat = control
    }

    static let topBarHeight: CGFloat = 44

    static let addressBarMaxWidth: CGFloat = 620

    static func edgeHandle(along axis: Axis) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: accent.opacity(0), location: 0),
                .init(color: accent, location: 0.08),
                .init(color: accent, location: 0.92),
                .init(color: accent.opacity(0), location: 1),
            ],
            startPoint: axis == .vertical ? .top : .leading,
            endPoint: axis == .vertical ? .bottom : .trailing
        )
    }

    static let edgeHandle = edgeHandle(along: .vertical)

    static func chrome(_ opacity: Double) -> Color {
        Color.primary.opacity(opacity)
    }

    enum Wash {
        static let none = chrome(0)
        static let faint = chrome(0.04)
        static let hairline = chrome(0.06)
        static let hover = chrome(0.08)
        static let selection = chrome(0.12)
        static let strong = chrome(0.16)
        static let outline = chrome(0.22)
        static let emphasis = chrome(0.30)
        static let mark = chrome(0.62)
        static let scrim = chrome(0.55)
    }

    enum Motion {
        static let quick: Animation = .easeOut(duration: 0.12)
        static let settle: Animation = .easeOut(duration: 0.18)
        static let drift: Animation = .easeOut(duration: 0.25)
    }

    enum Font {
        static let title: SwiftUI.Font = .system(size: 13, weight: .medium)
        static let rowTitle: SwiftUI.Font = .system(size: 12.5, weight: .medium)
        static let row: SwiftUI.Font = .system(size: 12.5)
        static let control: SwiftUI.Font = .system(size: 12, weight: .medium)
        static let body: SwiftUI.Font = .system(size: 12)
        static let secondary: SwiftUI.Font = .system(size: 11.5)
        static let label: SwiftUI.Font = .system(size: 11)
        static let caption: SwiftUI.Font = .system(size: 10.5)
        static let badge: SwiftUI.Font = .system(size: 10, weight: .semibold)
        static let micro: SwiftUI.Font = .system(size: 10)
    }

    private static func adaptive(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
    }
}
