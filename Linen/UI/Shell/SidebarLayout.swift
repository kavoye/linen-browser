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
    static let rowControlExtent: CGFloat = 20

    static let rowIconSpacing: CGFloat = 8
    static var fullContentInset: CGFloat {
        LoomChrome.canvasInset - LoomChrome.sidebarContentBalanceOffset
    }

    static let iconsContentInset: CGFloat = 8

    static func rowContentPadding(style: SidebarStyle) -> CGFloat {
        style == .icons ? 0 : 9
    }

    static func contentInset(style: SidebarStyle) -> CGFloat {
        style == .icons ? iconsContentInset : fullContentInset
    }

    static let controlHeight: CGFloat = 32

    static func controlMaxWidth(style: SidebarStyle) -> CGFloat {
        style == .icons ? .infinity : controlHeight
    }
    static let defaultWidth: CGFloat = 268
    static let defaultSnapDistance: CGFloat = 8

    static let iconsSnap: CGFloat = 150

    static func clampWidth(_ width: CGFloat, container: CGFloat) -> CGFloat {
        let ceiling = container > 0
            ? max(minWidth, min(maxWidth, container * maxWindowFraction))
            : maxWidth
        return min(max(width, minWidth), ceiling)
    }

    static func topControlsOpacity(isShowing: Bool) -> Double {
        isShowing ? 1 : 0
    }

    static let permanentToggleSlot: CGFloat = 36

    static func permanentToggleLeading(windowControlsInset: CGFloat) -> CGFloat {
        windowControlsInset > 0 ? windowControlsInset : 10
    }

    static func toolbarLeadingPadding(
        isVisible: Bool,
        style: SidebarStyle,
        windowControlsInset: CGFloat,
        contentInset: CGFloat
    ) -> CGFloat {
        guard !isVisible || style == .icons else { return 0 }
        let occupiedLeadingWidth = isVisible ? iconsWidth : 0
        return max(
            0,
            permanentToggleLeading(windowControlsInset: windowControlsInset)
                + permanentToggleSlot
                - occupiedLeadingWidth
                - contentInset
        )
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
    var isFloating: Bool {
        isPeeking && !isVisible
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

struct LoomColumnResizeHandle: View {
    let grabWidth: CGFloat
    let onLightPage: Bool
    let isDragging: Bool
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: (CGFloat) -> Void
    let onReset: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack {
            Color.clear

            LoomResizePill(
                axis: .vertical,
                isVisible: isDragging || isHovering,
                isDragging: isDragging,
                onLightPage: onLightPage
            )
        }
        .frame(width: grabWidth)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .pointerStyle(.columnResize)
        .onHover { inside in
            isHovering = inside
        }
        .gesture(drag)
        .onTapGesture(count: 2) { onReset() }
        .animation(Theme.Motion.quick, value: isHovering)
        .animation(Theme.Motion.quick, value: isDragging)
        .help("Drag to resize · double-click to reset")
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
