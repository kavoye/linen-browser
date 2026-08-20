// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

enum SidebarStyle: String {
    case full
    case icons
}

enum SidebarMetrics {
    static let minWidth: CGFloat = 190
    static let maxWidth: CGFloat = 420
    static let maxWindowFraction: CGFloat = 0.4

    static let iconsWidth: CGFloat = 56

    static func splitEndWidth(style: SidebarStyle) -> CGFloat {
        style == .icons ? 8 : 14
    }

    static let rowIconSize: CGFloat = 16
    static let rowIconSpacing: CGFloat = 8

    static func rowContentPadding(style: SidebarStyle) -> CGFloat {
        style == .icons ? 0 : 9
    }
    static let defaultWidth: CGFloat = 268
    static let defaultSnapDistance: CGFloat = 8

    static let iconsSnap: CGFloat = 150

    static let grabWidth: CGFloat = 8

    static func clampWidth(_ width: CGFloat, container: CGFloat) -> CGFloat {
        let ceiling = container > 0
            ? max(minWidth, min(maxWidth, container * maxWindowFraction))
            : maxWidth
        return min(max(width, minWidth), ceiling)
    }

    static func topControlsOpacity(isShowing: Bool) -> Double {
        isShowing ? 1 : 0
    }

    static func windowControlsPadding(
        isVisible: Bool,
        style: SidebarStyle,
        windowControlsInset: CGFloat
    ) -> CGFloat {
        let occupiedLeadingWidth: CGFloat
        if !isVisible {
            occupiedLeadingWidth = 0
        } else if style == .icons {
            occupiedLeadingWidth = iconsWidth + 1
        } else {
            occupiedLeadingWidth = windowControlsInset
        }
        return max(0, windowControlsInset - occupiedLeadingWidth - 10)
    }
}

enum SidebarTogglePlacement {
    static func inNavBar(isVisible: Bool, style: SidebarStyle) -> Bool {
        !isVisible || style == .icons
    }

    static func inSidebarTop(style: SidebarStyle) -> Bool {
        style == .full
    }
}

enum SidebarPeekShield {
    static func suppressesHover(
        isVisible: Bool,
        isPeeking: Bool,
        viewMaxX: CGFloat,
        width: CGFloat,
        isMediaPicture: Bool
    ) -> Bool {
        if isMediaPicture {
            return true
        }
        return !isVisible && isPeeking && viewMaxX > width
    }
}

@MainActor
@Observable
final class SidebarLayout {
    private enum Key {
        static let visible = "sidebar.visible"
        static let style = "sidebar.style"
        static let width = "sidebar.width"
    }

    private(set) var isVisible: Bool {
        didSet { if isVisible != oldValue { onShowingChange?() } }
    }
    private(set) var style: SidebarStyle
    private(set) var width: CGFloat
    private(set) var dragWidth: CGFloat?

    var isPeeking = false {
        didSet { if isPeeking != oldValue { onShowingChange?() } }
    }

    @ObservationIgnored var onShowingChange: (() -> Void)?

    private var dragOrigin: CGFloat?
    @ObservationIgnored private var isDefaultWidthSnapped = false

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isVisible = defaults.object(forKey: Key.visible) as? Bool ?? true
        style = defaults.string(forKey: Key.style).flatMap(SidebarStyle.init(rawValue:)) ?? .full
        let stored = defaults.double(forKey: Key.width)
        width = stored > 0 ? CGFloat(stored) : SidebarMetrics.defaultWidth
    }

    // MARK: - Derived

    var isShowing: Bool {
        isVisible || isPeeking
    }
    var isDragging: Bool {
        dragOrigin != nil
    }

    func openWidth(in container: CGFloat) -> CGFloat {
        if let dragWidth {
            return dragWidth
        }
        guard style == .full else { return SidebarMetrics.iconsWidth }
        return SidebarMetrics.clampWidth(width, container: container)
    }

    // MARK: - Visibility

    func toggleVisible() {
        isVisible.toggle()
        isPeeking = false
        defaults.set(isVisible, forKey: Key.visible)
    }

    func show() {
        guard !isVisible else { return }
        isVisible = true
        isPeeking = false
        defaults.set(true, forKey: Key.visible)
    }

    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        toggleVisible()
    }

    var isIconsOnly: Bool {
        style == .icons
    }

    func setIconsOnly(_ iconsOnly: Bool) {
        setStyle(iconsOnly ? .icons : .full)
    }

    func setStyle(_ newStyle: SidebarStyle) {
        guard newStyle != style else { return }
        style = newStyle
        if newStyle == .full, width < SidebarMetrics.minWidth {
            width = SidebarMetrics.defaultWidth
        }
        dragWidth = nil
        persistShape()
    }

    func resetWidth() {
        style = .full
        width = SidebarMetrics.defaultWidth
        dragWidth = nil
        persistShape()
    }

    // MARK: - Drag

    func dragChanged(translation: CGFloat, container: CGFloat) {
        if dragOrigin == nil {
            dragOrigin = openWidth(in: container)
            isDefaultWidthSnapped = style == .full
                && abs((dragOrigin ?? 0) - SidebarMetrics.defaultWidth) <= SidebarMetrics.defaultSnapDistance
        }
        apply((dragOrigin ?? 0) + translation, releasing: false, container: container)
    }

    func dragEnded(translation: CGFloat, container: CGFloat) {
        apply((dragOrigin ?? openWidth(in: container)) + translation, releasing: true, container: container)
        dragOrigin = nil
        dragWidth = nil
        isDefaultWidthSnapped = false
        persistShape()
    }

    private func apply(_ proposed: CGFloat, releasing: Bool, container: CGFloat) {
        let proposedStyle: SidebarStyle = proposed < SidebarMetrics.iconsSnap ? .icons : .full
        let snapsToDefault = proposedStyle == .full
            && abs(proposed - SidebarMetrics.defaultWidth) <= SidebarMetrics.defaultSnapDistance
        let snapped = snapsToDefault
            ? SidebarMetrics.defaultWidth
            : proposed

        let ceiling = container > 0
            ? max(
                SidebarMetrics.minWidth,
                min(SidebarMetrics.maxWidth, container * SidebarMetrics.maxWindowFraction)
            )
            : SidebarMetrics.maxWidth
        let floor = proposedStyle == .full ? SidebarMetrics.minWidth : SidebarMetrics.iconsWidth
        let liveWidth = min(max(snapped, floor), ceiling)

        if !releasing {
            if style != proposedStyle || (snapsToDefault && !isDefaultWidthSnapped) {
                performSnapFeedback()
            }
            style = proposedStyle
            isDefaultWidthSnapped = snapsToDefault
            dragWidth = liveWidth
            return
        }

        style = proposedStyle
        isDefaultWidthSnapped = false
        if proposedStyle == .icons {
            dragWidth = SidebarMetrics.iconsWidth
        } else {
            width = SidebarMetrics.clampWidth(snapped, container: container)
            dragWidth = width
        }
    }

    private func performSnapFeedback() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private func persistShape() {
        defaults.set(style.rawValue, forKey: Key.style)
        defaults.set(Double(width), forKey: Key.width)
    }
}

extension EnvironmentValues {
    @Entry var sidebarStyle: SidebarStyle = .full

    @Entry var sidebarWidth: CGFloat = SidebarMetrics.defaultWidth
}

struct ColumnEdgeHandle: View {
    let edge: HorizontalEdge
    let grabWidth: CGFloat
    let isDragging: Bool
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: (CGFloat) -> Void
    let onReset: () -> Void

    @State private var isHovering = false
    @State private var isArmed = false

    private static let lineThickness: CGFloat = 2

    static let armDelay: Duration = .milliseconds(260)

    private var active: Bool {
        isArmed || isDragging
    }

    private var reach: CGFloat {
        edge == .leading ? -1 : 1
    }

    private var alignment: Alignment {
        edge == .leading ? .leading : .trailing
    }

    var body: some View {
        Capsule()
            .fill(Theme.edgeHandle)
            .opacity(active ? 1 : 0)
            .frame(width: Self.lineThickness)
            .frame(width: grabWidth, alignment: alignment)
            .contentShape(Rectangle())
            .pointerStyle(active ? .columnResize : nil)
            .overlay {
                ColumnEdgeCursorArea(isActive: active)
                    .allowsHitTesting(false)
            }
            .onHover { inside in
                isHovering = inside
                if !inside {
                    isArmed = false
                }
            }
            .task(id: isHovering) {
                guard isHovering else { return }
                try? await Task.sleep(for: Self.armDelay)
                guard !Task.isCancelled else { return }
                isArmed = true
            }
            .gesture(drag)
            .onTapGesture(count: 2) { onReset() }
            .animation(Theme.Motion.quick, value: active)
            .help("Drag to resize · double-click to reset")
            .offset(x: reach)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                NSCursor.columnResize.set()
                withTransaction(Transaction(animation: nil)) {
                    onDragChanged(value.translation.width)
                }
            }
            .onEnded { value in
                withTransaction(Transaction(animation: nil)) {
                    onDragEnded(value.translation.width)
                }
            }
    }
}

private struct ColumnEdgeCursorArea: NSViewRepresentable {
    let isActive: Bool

    func makeNSView(context: Context) -> CursorArea {
        let view = CursorArea()
        view.isActive = isActive
        return view
    }

    func updateNSView(_ nsView: CursorArea, context: Context) {
        nsView.isActive = isActive
    }

    final class CursorArea: NSView {
        var isActive = false {
            didSet {
                guard isActive != oldValue, window != nil else { return }
                if isActive {
                    NSCursor.columnResize.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
        }

        private var area: NSTrackingArea?

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area {
                removeTrackingArea(area)
            }
            let added = NSTrackingArea(
                rect: .zero,
                options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                owner: self
            )
            addTrackingArea(added)
            area = added
        }

        override func mouseMoved(with event: NSEvent) {
            guard isActive else { return }
            NSCursor.columnResize.set()
        }
    }
}

struct SidebarDivider: View {
    let layout: SidebarLayout
    let containerWidth: CGFloat

    var body: some View {
        ColumnEdgeHandle(
            edge: .trailing,
            grabWidth: SidebarMetrics.grabWidth,
            isDragging: layout.isDragging,
            onDragChanged: { layout.dragChanged(translation: $0, container: containerWidth) },
            onDragEnded: { layout.dragEnded(translation: $0, container: containerWidth) },
            onReset: { layout.resetWidth() }
        )
    }
}
