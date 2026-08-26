// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct QuietIconButton: View {
    let symbol: String
    let isOn: Bool
    var tint: Color?
    let help: String
    let action: () -> Void

    @State private var hovering = false

    private var ink: AnyShapeStyle {
        if let tint {
            return AnyShapeStyle(tint)
        }
        return isOn ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Theme.Font.rowTitle)
                .frame(width: 28, height: 28)
                .hoverBackground(isActive: isOn || hovering, tint: tint, in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(ink)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .help(help)
    }
}

struct ToolbarButton: View {
    let symbol: String
    let enabled: Bool
    var isOn = false
    var highlightsWhenOn = true
    var help: String = ""
    var heldMenu: (() -> NSMenu?)?
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.chromeIsLight) private var chromeIsLight

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 28)
                .hoverBackground(
                    isActive: (hovering && enabled) || (isOn && highlightsWhenOn)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            ChromeInk.glyph(
                onLight: chromeIsLight,
                enabled: enabled,
                hovering: hovering || (isOn && highlightsWhenOn)
            )
        )
        .disabled(!enabled)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .onHover { hovering = $0 }
        .overlay {
            if let heldMenu, enabled {
                ToolbarHoldCatcher(hovering: $hovering, menu: heldMenu, action: action)
                    .holdsWindowStillOnHover()
            }
        }
        .animation(Theme.Motion.quick, value: hovering)
        .help(help)
    }
}

struct ToolbarChip: View {
    let symbol: String
    let label: LocalizedStringResource
    var isDestructive = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(Theme.Font.caption)
                Text(label)
                    .font(Theme.Font.control)
            }
            .foregroundStyle(isDestructive && hovering ? .red : .primary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .controlGlassSurface(
                isActive: hovering,
                tint: isDestructive && hovering ? .red : nil,
                in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
            )
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .onHover { hovering = isEnabled && $0 }
        .animation(Theme.Motion.quick, value: hovering)
    }
}
