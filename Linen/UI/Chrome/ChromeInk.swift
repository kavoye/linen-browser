// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

enum ChromeInk {
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
}

private struct ChromeButtonPlate: ViewModifier {
    let isLit: Bool

    @Environment(\.chromeIsLight) private var chromeIsLight

    private static let litOpacity = 0.08

    func body(content: Content) -> some View {
        content
            .background(
                ChromeInk.wash(onLight: chromeIsLight, opacity: isLit ? Self.litOpacity : 0),
                in: RoundedRectangle(cornerRadius: Theme.Radius.hover)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.hover))
            .animation(Theme.Motion.quick, value: isLit)
    }
}

extension View {
    func chromeButtonPlate(isLit: Bool) -> some View {
        modifier(ChromeButtonPlate(isLit: isLit))
    }
}

extension View {
    func hoverVerified(_ hovering: Binding<Bool>, onClear: (() -> Void)? = nil) -> some View {
        modifier(HoverVerification(hovering: hovering, onClear: onClear))
    }
}

private struct HoverVerification: ViewModifier {
    @Binding var hovering: Bool
    let onClear: (() -> Void)?

    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .task(id: hovering) {
                guard hovering else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled, hovering else { return }
                    guard let pointer = PointerLocation.inGlobalSpace else { continue }
                    if !frame.contains(pointer) {
                        hovering = false
                        onClear?()
                        return
                    }
                }
            }
    }
}

@MainActor
enum PointerLocation {
    static var inGlobalSpace: CGPoint? {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let content = window.contentView
        else { return nil }
        let contentInScreen = window.convertToScreen(content.convert(content.bounds, to: nil))
        let mouse = NSEvent.mouseLocation
        return CGPoint(x: mouse.x - contentInScreen.minX, y: contentInScreen.maxY - mouse.y)
    }
}

struct ChromeIcon: View {
    let symbol: String
    var size: CGFloat = 10.5
    var weight: Font.Weight = .medium
    var isEnabled = true
    var isSubdued = false
    var tint: Color?
    var extent: CGFloat = 16
    var help: String = ""
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.chromeIsLight) private var chromeIsLight

    private var style: AnyShapeStyle {
        if let tint {
            return AnyShapeStyle(tint.opacity(hovering ? 1 : 0.85))
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
                .frame(width: extent, height: extent)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering = $0 }
        .hoverVerified($hovering)
        .animation(Theme.Motion.quick, value: hovering)
        .help(help)
        .toolTipText(help)
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

extension View {
    /// An `NSView` tooltip, which the view under the pointer answers even when
    /// an ancestor's `.help` rect covers it.
    func toolTipText(_ text: String) -> some View {
        overlay(ToolTipArea(text: text))
    }
}

struct ToolTipArea: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> TipArea {
        let view = TipArea()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: TipArea, context: Context) {
        apply(to: nsView)
    }

    func apply(to view: TipArea) {
        let wanted = text.isEmpty ? nil : text
        guard view.toolTip != wanted else { return }
        view.toolTip = wanted
    }

    final class TipArea: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

extension EnvironmentValues {
    @Entry var chromeIsLight: Bool = false
}
