// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

extension View {
    func holdsWindowStillOnHover() -> some View {
        background { WindowStillWhileHovered() }
    }
}

private struct WindowStillWhileHovered: NSViewRepresentable {
    func makeNSView(context: Context) -> HoldView {
        HoldView()
    }

    func updateNSView(_ nsView: HoldView, context: Context) {}

    static func dismantleNSView(_ nsView: HoldView, coordinator: ()) {
        nsView.release()
    }

    final class HoldView: NSView {
        private var isHolding = false

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            ))
            releaseIfPointerLeft()
        }

        private func releaseIfPointerLeft() {
            guard isHolding, let window else { return }
            let local = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            if !bounds.contains(local) {
                release()
            }
        }

        override func mouseEntered(with event: NSEvent) {
            guard let window, !isHolding else { return }
            isHolding = true
            window.isMovable = false
        }

        override func mouseExited(with event: NSEvent) {
            release()
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            release()
        }

        func release() {
            guard isHolding else { return }
            isHolding = false
            window?.isMovable = true
        }
    }
}
