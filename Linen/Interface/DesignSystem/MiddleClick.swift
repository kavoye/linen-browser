// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

extension View {
    func onMiddleClick(perform action: @escaping () -> Void) -> some View {
        overlay(MiddleClickCatcher(action: action))
    }
}

private struct MiddleClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.action = action
    }

    final class CatcherView: NSView {
        var action: (() -> Void)?

        override var mouseDownCanMoveWindow: Bool {
            false
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard super.hitTest(point) != nil,
                  let event = window?.currentEvent ?? NSApp.currentEvent,
                  event.buttonNumber == 2
            else { return nil }
            switch event.type {
            case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
                return self
            default:
                return nil
            }
        }

        override func otherMouseDown(with event: NSEvent) {}

        override func otherMouseUp(with event: NSEvent) {
            guard event.buttonNumber == 2,
                  bounds.contains(convert(event.locationInWindow, from: nil))
            else { return }
            action?()
        }
    }
}
