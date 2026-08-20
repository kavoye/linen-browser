// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct QuietIconButton: View {
    let symbol: String
    let isOn: Bool
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Theme.Font.rowTitle)
                .frame(width: 28, height: 28)
                .background(
                    isOn ? Theme.Wash.selection : hovering ? Theme.Wash.hover : Theme.Wash.none,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.hover)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isOn ? .primary : .secondary)
        .onHover { hovering = $0 }
        .hoverVerified($hovering)
        .animation(Theme.Motion.quick, value: hovering)
        .help(help)
    }
}

struct ToolbarButton: View {
    let symbol: String
    let enabled: Bool
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
                .chromeButtonPlate(isLit: hovering && enabled)
        }
        .buttonStyle(.plain)
        .foregroundStyle(ChromeInk.glyph(onLight: chromeIsLight, enabled: enabled, hovering: hovering))
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .hoverVerified($hovering)
        .overlay {
            if let heldMenu, enabled {
                ToolbarHoldCatcher(hovering: $hovering, menu: heldMenu, action: action)
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
            .background(
                hovering ? Theme.Wash.hover : Theme.Wash.faint,
                in: RoundedRectangle(cornerRadius: Theme.Radius.control)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .strokeBorder(hovering ? Theme.Wash.strong : Theme.Wash.hover, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .onHover { hovering = isEnabled && $0 }
        .animation(Theme.Motion.quick, value: hovering)
    }
}
