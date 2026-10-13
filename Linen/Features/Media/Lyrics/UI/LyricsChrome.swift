// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct LyricsChromeButton: View {
    let symbol: String
    let help: LocalizedStringResource
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            LyricsGlyph(symbol: symbol, hovering: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(Text(help))
    }
}

/// The same button, opening a menu under itself rather than under the pointer.
/// A SwiftUI `Menu` is bridged to an NSPopUpButton, which paints its own label
/// and ignores the tint and the hover the timing buttons use.

struct LyricsChromeMenuButton: View {
    let symbol: String
    let help: LocalizedStringResource
    let menu: () -> NSMenu

    @State private var anchor = MenuAnchorBox()
    @State private var hovering = false

    var body: some View {
        Button {
            let menu = menu()
            guard let view = anchor.view else {
                menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
                return
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: view)
        } label: {
            LyricsGlyph(symbol: symbol, hovering: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(Text(help))
        .background { MenuAnchor(box: anchor) }
    }
}

@MainActor
final class MenuAnchorBox {
    weak var view: NSView?
}

struct MenuAnchor: NSViewRepresentable {
    let box: MenuAnchorBox

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        box.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        box.view = nsView
    }
}

private struct LyricsGlyph: View {
    let symbol: String
    let hovering: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(hovering ? 0.95 : 0.55))
            .hoverLift(hovering)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .environment(\.chromeIsLight, false)
            .environment(\.chromeWash, .of(nil, isLight: false))
    }
}
