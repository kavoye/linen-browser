// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

extension View {
    func arrowlessPopover<Content: View>(
        isPresented: Binding<Bool>,
        leadingWidth: CGFloat? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        background(ArrowlessPopoverAnchor(isPresented: isPresented, leadingWidth: leadingWidth, content: content))
    }
}

private struct ArrowlessPopoverAnchor<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    let leadingWidth: CGFloat?
    let content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        let environment = context.environment
        coordinator.dismiss = { if isPresented { isPresented = false } }
        coordinator.growsFromLeadingCorner = leadingWidth != nil
        coordinator.hosting.rootView = AnyView(
            content().transformEnvironment(\.self) { $0 = environment }
        )
        let popover = coordinator.popover
        if isPresented, !popover.isShown, view.window != nil {
            popover.appearance = NSAppearance(named: environment.chromeIsLight ? .aqua : .darkAqua)
            let anchor = positioningView(in: view, coordinator: coordinator)
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        } else if !isPresented, popover.isShown {
            popover.close()
        }
    }

    private func positioningView(in view: NSView, coordinator: Coordinator) -> NSView {
        guard let leadingWidth else { return view }
        let anchor = coordinator.leadingAnchor
        anchor.frame = CGRect(x: 0, y: 0, width: leadingWidth, height: view.bounds.height)
        if anchor.superview !== view {
            view.addSubview(anchor)
        }
        return anchor
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.popover.close()
    }

    final class Coordinator: NSObject, NSPopoverDelegate {
        let popover = NSPopover()
        let hosting = NSHostingController(rootView: AnyView(EmptyView()))
        let leadingAnchor = NSView()
        var dismiss: () -> Void = {}
        var growsFromLeadingCorner = false

        override init() {
            super.init()
            hosting.sizingOptions = .preferredContentSize
            popover.contentViewController = hosting
            popover.behavior = .transient
            popover.delegate = self
            let hidesAnchor = Selector(("setShouldHideAnchor:"))
            if popover.responds(to: hidesAnchor) {
                popover.setValue(true, forKey: "shouldHideAnchor")
            }
        }

        func popoverWillShow(_ notification: Notification) {
            pinAnchorToLeadingCorner()
        }

        func popoverWillClose(_ notification: Notification) {
            pinAnchorToLeadingCorner()
        }

        func popoverDidClose(_ notification: Notification) {
            dismiss()
        }

        private func pinAnchorToLeadingCorner() {
            guard growsFromLeadingCorner,
                  let window = hosting.view.window,
                  window.responds(to: Selector(("setAnchorPoint:")))
            else { return }
            let leading = hosting.view.convert(hosting.view.bounds, to: nil).minX
            window.setValue(NSPoint(x: leading, y: 0), forKey: "anchorPoint")
        }
    }
}
