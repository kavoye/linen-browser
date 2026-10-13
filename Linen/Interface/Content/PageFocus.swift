// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

extension View {
    func takesFocusOnClick() -> some View {
        modifier(TakesFocusOnClick())
    }
}

private struct TakesFocusOnClick: ViewModifier {
    @State private var anchor = PageFocusAnchor()

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .simultaneousGesture(SpatialTapGesture().onEnded { anchor.view?.takeFocus(at: $0.location) })
            .background(PageFocusView(anchor: anchor))
    }
}

private final class PageFocusAnchor {
    weak var view: PageFocusNSView?
}

private struct PageFocusView: NSViewRepresentable {
    let anchor: PageFocusAnchor

    func makeNSView(context: Context) -> PageFocusNSView {
        let view = PageFocusNSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: PageFocusNSView, context: Context) {
        anchor.view = nsView
    }
}

final class PageFocusNSView: NSView {
    override var acceptsFirstResponder: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func takeFocus(at location: CGPoint) {
        guard let window else { return }
        if var responder = window.firstResponder as? NSView, responder !== self {
            if let editor = responder as? NSTextView, editor.isFieldEditor, let field = editor.delegate as? NSView {
                responder = field
            }
            let point = convert(CGPoint(x: location.x, y: isFlipped ? location.y : bounds.height - location.y), to: nil)
            if responder.convert(responder.bounds, to: nil).contains(point) {
                return
            }
        }
        window.makeFirstResponder(self)
    }
}
