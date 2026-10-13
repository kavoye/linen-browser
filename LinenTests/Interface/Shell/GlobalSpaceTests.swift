// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import Testing

@testable import Linen

@MainActor
final class GlobalSpaceProbeBox {
    var rect: CGRect = .zero
}

private struct GlobalSpaceProbe: View {
    let box: GlobalSpaceProbeBox

    var body: some View {
        VStack(spacing: 0) {
            Color.red
                .frame(width: 50, height: 20)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { box.rect = $0 }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// `ClickOutsideCatcher` measures the media card in SwiftUI's `.global` space
/// and compares mouse events against it, so what that space is has to hold:
/// the hosting view's own top-left corner, y downward — not the window's
/// bottom-left base coordinates a mouse event arrives in.
@MainActor
struct GlobalSpaceTests {
    @Test func globalSpaceStartsAtTheHostingViewsTopLeft() {
        let box = GlobalSpaceProbeBox()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let host = NSHostingView(rootView: GlobalSpaceProbe(box: box))
        host.safeAreaRegions = []
        host.frame = root.bounds
        root.addSubview(host)
        window.contentView = root
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()

        #expect(box.rect == CGRect(x: 175, y: 0, width: 50, height: 20))
        #expect(!root.isFlipped)
    }
}
