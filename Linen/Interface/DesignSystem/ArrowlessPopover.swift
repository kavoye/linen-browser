// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

extension View {
    func arrowlessPopover<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        background(ArrowlessPopoverAnchor(isPresented: isPresented, content: content))
    }
}

private struct ArrowlessPopoverAnchor<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
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
        coordinator.hosting.rootView = AnyView(
            content().transformEnvironment(\.self) { $0 = environment }
        )
        let popover = coordinator.popover
        if isPresented, !popover.isShown, view.window != nil {
            popover.appearance = NSAppearance(named: environment.chromeIsLight ? .aqua : .darkAqua)
            popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
        } else if !isPresented, popover.isShown {
            popover.close()
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.popover.close()
    }

    final class Coordinator: NSObject, NSPopoverDelegate {
        let popover = NSPopover()
        let hosting = NSHostingController(rootView: AnyView(EmptyView()))
        var dismiss: () -> Void = {}

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

        func popoverDidClose(_ notification: Notification) {
            dismiss()
        }
    }
}
