// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

private struct SidebarRowSelectionEffect: ViewModifier {
    let isSelected: Bool
    let isHovering: Bool
    var hoverTint: Color?
    var glassTint: Color?
    var radius = Theme.Radius.hover

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.windowColorScheme) private var windowColorScheme
    @Environment(\.chromeWash) private var wash

    private var fill: AnyShapeStyle {
        guard isHovering, !isSelected else { return AnyShapeStyle(.clear) }
        if let hoverTint {
            return AnyShapeStyle(hoverTint.opacity(0.18))
        }
        return ChromeInk.hoverStyle(on: wash)
    }

    private var wearsGlass: Bool {
        isSelected
    }

    private var wearsPanelGlass: Bool {
        windowColorScheme == .dark
    }

    private var glass: Glass {
        if wearsPanelGlass {
            guard let glassTint else { return .regular }
            return .regular.tint(glassTint.opacity(0.32))
        }
        let base = glassTint ?? Theme.windowBackground
        return .clear.tint(base.opacity(glassTint == nil ? 0.34 : 0.16))
    }

    private var surfaceWash: Color {
        guard let glassTint else { return Color.primary.opacity(0.06) }
        return glassTint.opacity(0.10)
    }

    private var surfaceEdge: Color {
        guard let glassTint else { return Color.primary.opacity(0.12) }
        return glassTint.opacity(0.24)
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            .background {
                ZStack {
                    if wearsGlass {
                        Color.clear.glassEffect(glass, in: shape)
                        if !wearsPanelGlass {
                            shape.fill(surfaceWash)
                            shape.strokeBorder(surfaceEdge, lineWidth: 1)
                        }
                    }
                    shape.fill(fill)
                }
                .environment(\.colorScheme, windowColorScheme)
                .allowsHitTesting(false)
            }
    }
}

extension View {
    func sidebarHoverFill<S: InsettableShape>(
        isHovering: Bool,
        tint: Color? = nil,
        in shape: S
    ) -> some View {
        hoverBackground(isActive: isHovering, tint: tint, in: shape)
            .contentShape(shape)
    }
}

extension View {
    func sidebarRowSelectionEffect(
        isSelected: Bool,
        isHovering: Bool,
        hoverTint: Color? = nil,
        glassTint: Color? = nil,
        radius: CGFloat = Theme.Radius.hover
    ) -> some View {
        modifier(SidebarRowSelectionEffect(
            isSelected: isSelected,
            isHovering: isHovering,
            hoverTint: hoverTint,
            glassTint: glassTint,
            radius: radius
        ))
    }
}
