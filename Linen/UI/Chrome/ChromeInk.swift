// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

enum ChromeInk {
    static let lightSelectionFillOpacity = 0.17
    static let darkSelectionFillOpacity = 0.22

    static func glyphOpacity(onLight: Bool, enabled: Bool = true, hovering: Bool = false, subdued: Bool = false) -> Double {
        if !enabled {
            return onLight ? 0.25 : 0.3
        }
        if hovering {
            return 1
        }
        if subdued {
            return onLight ? 0.45 : 0.5
        }
        return onLight ? 0.75 : 0.85
    }

    static func glyph(onLight: Bool, enabled: Bool = true, hovering: Bool = false, subdued: Bool = false) -> AnyShapeStyle {
        let base: Color = onLight ? .black : .white
        let opacity = glyphOpacity(onLight: onLight, enabled: enabled, hovering: hovering, subdued: subdued)
        return AnyShapeStyle(base.opacity(opacity))
    }

    static func wash(onLight: Bool, opacity: Double) -> Color {
        (onLight ? Color.black : Color.white).opacity(opacity)
    }

    static var hoverStyle: AnyShapeStyle {
        AnyShapeStyle(Color.primary.opacity(0.10))
    }

    static func selectionTint(onLight: Bool) -> Color {
        wash(
            onLight: onLight,
            opacity: onLight ? lightSelectionFillOpacity : darkSelectionFillOpacity
        )
    }
}

private struct GlassSurface<S: Shape>: ViewModifier {
    let isActive: Bool
    let isEnabled: Bool
    let tint: Color?
    let shape: S

    private var hoverFill: AnyShapeStyle {
        isActive ? ChromeInk.hoverStyle : AnyShapeStyle(.clear)
    }

    func body(content: Content) -> some View {
        content
            .glassEffect(isEnabled ? .regular : .identity, in: shape)
            .background { shape.fill(hoverFill) }
            .contentShape(shape)
    }
}

extension View {
    func glassSurface<S: Shape>(
        isActive: Bool = false,
        isEnabled: Bool = true,
        tint: Color? = nil,
        in shape: S
    ) -> some View {
        modifier(GlassSurface(
            isActive: isActive,
            isEnabled: isEnabled,
            tint: tint,
            shape: shape
        ))
    }
}

private struct ControlGlassSurface<S: InsettableShape>: ViewModifier {
    let isActive: Bool
    let tint: Color?
    let isLifted: Bool
    let shape: S

    private var glass: Glass {
        if let tint {
            return .clear.tint(tint.opacity(isActive ? 0.16 : 0.07))
        }
        if isLifted {
            return .clear.tint(Theme.controlSurface.opacity(isActive ? 0.62 : 0.48))
        }
        return .clear.tint(Theme.windowBackground.opacity(isActive ? 0.34 : 0.26))
    }

    private var surfaceWash: Color {
        if let tint {
            return tint.opacity(isActive ? 0.10 : 0.045)
        }
        return Color.primary.opacity(isActive ? 0.06 : 0.04)
    }

    private var outline: Color {
        if let tint {
            return tint.opacity(isActive ? 0.24 : 0.13)
        }
        if isLifted {
            return Color.primary.opacity(isActive ? 0.20 : 0.14)
        }
        return Color.primary.opacity(isActive ? 0.12 : 0.08)
    }

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape
                        .fill(.clear)
                        .glassEffect(glass, in: shape)

                    shape.fill(surfaceWash)
                }
            }
            .overlay { shape.strokeBorder(outline, lineWidth: 1) }
            .contentShape(shape)
    }
}

extension View {
    func controlGlassSurface<S: InsettableShape>(
        isActive: Bool = false,
        tint: Color? = nil,
        isLifted: Bool = false,
        in shape: S
    ) -> some View {
        modifier(
            ControlGlassSurface(isActive: isActive, tint: tint, isLifted: isLifted, shape: shape)
        )
    }
}

private struct HoverBackground<S: Shape>: ViewModifier {
    let isActive: Bool
    let tint: Color?
    let shape: S

    private var fill: AnyShapeStyle {
        isActive ? ChromeInk.hoverStyle : AnyShapeStyle(.clear)
    }

    func body(content: Content) -> some View {
        content
            .background { shape.fill(fill) }
            .contentShape(shape)
    }
}

extension View {
    func hoverBackground<S: Shape>(
        isActive: Bool,
        tint: Color? = nil,
        in shape: S
    ) -> some View {
        modifier(HoverBackground(isActive: isActive, tint: tint, shape: shape))
    }

    func hoverBackground(isActive: Bool) -> some View {
        hoverBackground(isActive: isActive, in: Circle())
    }
}

private struct SelectionBackground<S: Shape>: ViewModifier {
    let isSelected: Bool
    let isHovering: Bool
    let hoverTint: Color?
    let rests: Bool
    let shape: S

    @Environment(\.colorScheme) private var colorScheme

    private var onLight: Bool {
        colorScheme == .light
    }

    private var glass: Glass {
        if isSelected {
            return .regular
        }
        if rests {
            return .regular
        }
        return .identity
    }

    private var hoverFill: AnyShapeStyle {
        isHovering && !isSelected
            ? ChromeInk.hoverStyle
            : AnyShapeStyle(.clear)
    }

    func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(hoverFill)
            }
            .glassEffect(glass, in: shape)
    }
}

extension View {
    func selectionBackground<S: Shape>(
        isSelected: Bool,
        isHovering: Bool,
        hoverTint: Color? = nil,
        rests: Bool = false,
        in shape: S
    ) -> some View {
        modifier(SelectionBackground(
            isSelected: isSelected,
            isHovering: isHovering,
            hoverTint: hoverTint,
            rests: rests,
            shape: shape
        ))
    }
}

extension Color {
    func deepened(by fraction: Double) -> Color {
        let base = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        guard let deeper = base.blended(withFraction: fraction, of: .black) else { return self }
        return Color(nsColor: deeper)
    }
}

struct ChromeIcon: View {
    let symbol: String
    var size: CGFloat = 10.5
    var weight: Font.Weight = .medium
    var isEnabled = true
    var isSubdued = false
    var tint: Color?
    var extent: CGFloat?
    var help: String = ""
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.chromeIsLight) private var chromeIsLight
    @Environment(\.chromeIconExtent) private var inheritedExtent

    private var side: CGFloat {
        extent ?? inheritedExtent
    }

    private var style: AnyShapeStyle {
        if let tint {
            return AnyShapeStyle(chromeIsLight ? tint.deepened(by: 0.28) : tint)
        }
        return ChromeInk.glyph(
            onLight: chromeIsLight,
            enabled: isEnabled,
            hovering: hovering,
            subdued: isSubdued
        )
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(style)
                .frame(width: side, height: side)
                .hoverBackground(isActive: hovering)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .help(help)
    }
}

extension ChromeIcon {
    static func rowControl(
        symbol: String,
        help: String = "",
        action: @escaping () -> Void
    ) -> ChromeIcon {
        ChromeIcon(
            symbol: symbol,
            size: 11,
            weight: .semibold,
            isSubdued: true,
            extent: 20,
            help: help,
            action: action
        )
    }
}

struct CloseButton: View {
    var help = String(localized: "Close Tab")
    let action: () -> Void

    var body: some View {
        ChromeIcon.rowControl(symbol: "xmark", help: help, action: action)
    }
}

extension EnvironmentValues {
    @Entry var chromeIsLight: Bool = false
    @Entry var chromeIconExtent: CGFloat = 16

    @Entry var windowColorScheme: ColorScheme = .dark
}
