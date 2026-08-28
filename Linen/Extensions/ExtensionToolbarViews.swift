// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import WebKit

struct ExtensionDrag {
    let id: String
    let origin: CGRect
    var translation: CGSize = .zero
    var landing = false
}

struct ExtensionActionsCluster: View {
    let manager: ExtensionManager
    let browser: BrowserModel
    let availableWidth: CGFloat?

    @State private var drag: ExtensionDrag?
    @State private var frames: [String: CGRect] = [:]
    @State private var overflowFrame: CGRect = .zero
    @State private var showingOverflow = false

    private nonisolated static let space = "extension-cluster"
    private static let slot: CGFloat = 32

    private var pinned: [InstalledExtension] {
        manager.pinnedExtensions
    }

    private var visible: [InstalledExtension] {
        guard let availableWidth,
              CGFloat(pinned.count) * Self.slot > availableWidth else { return pinned }
        let capacity = max(1, Int((availableWidth - Self.slot) / Self.slot))
        return Array(pinned.prefix(capacity))
    }

    private var collapsed: [InstalledExtension] {
        Array(pinned.dropFirst(visible.count))
    }

    private var overflowed: [InstalledExtension] {
        collapsed + manager.unpinnedExtensions
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(visible) { record in
                ExtensionActionButton(
                    manager: manager,
                    browser: browser,
                    record: record,
                    isLifted: drag?.id == record.id
                )
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) }
                    action: { frames[record.id] = $0 }
            }

            if !overflowed.isEmpty || drag != nil {
                ExtensionOverflowButton(
                    manager: manager,
                    records: overflowed,
                    collapsedCount: collapsed.count,
                    isArmed: isOverOverflow,
                    isPresented: $showingOverflow
                )
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) }
                    action: { overflowFrame = $0 }
            }
        }
        .coordinateSpace(.named(Self.space))
        .holdsWindowStillOnHover()
        // The gesture belongs to the container. A reorder rebuilds the dragged
        // button, and a rebuilt view never delivers `.onEnded`.
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
                .onChanged(dragChanged)
                .onEnded(dragEnded)
        )
        .overlay {
            ClusterMenuCatcher(
                extensionID: extensionID(atX:),
                menuForExtension: { manager.contextMenu(for: $0) }
            )
        }
        .overlay(alignment: .topLeading) { chip }
    }

    private func extensionID(atX x: CGFloat) -> String? {
        let visibleIDs = Set(visible.map(\.id))
        return frames.first { entry in
            visibleIDs.contains(entry.key) && entry.value.minX <= x && x < entry.value.maxX
        }?.key
    }

    @ViewBuilder
    private var chip: some View {
        if let drag, let record = pinned.first(where: { $0.id == drag.id }) {
            ExtensionArtwork(manager: manager, record: record)
                .frame(width: drag.origin.width, height: drag.origin.height)
                .background(
                    Theme.windowBackground.opacity(0.82),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .strokeBorder(Theme.Wash.selection, lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.3), radius: 11, y: 5)
                .scaleEffect(drag.landing ? 1 : 1.06)
                .opacity(drag.landing ? 0 : 1)
                .offset(x: chipX(drag), y: chipY(drag))
                .allowsHitTesting(false)
        }
    }

    private func chipX(_ drag: ExtensionDrag) -> CGFloat {
        guard !drag.landing else { return frames[drag.id]?.minX ?? drag.origin.minX }
        return drag.origin.minX + drag.translation.width
    }

    private func chipY(_ drag: ExtensionDrag) -> CGFloat {
        guard !drag.landing else { return frames[drag.id]?.minY ?? drag.origin.minY }
        return drag.origin.minY + max(-7, min(7, drag.translation.height))
    }

    // MARK: - Dragging

    private var carriedCentreX: CGFloat? {
        guard let drag, !drag.landing else { return nil }
        return drag.origin.midX + drag.translation.width
    }

    private var isOverOverflow: Bool {
        guard let carriedCentreX, overflowFrame.width > 0 else { return false }
        return carriedCentreX >= overflowFrame.minX - 4
    }

    private func dragChanged(_ value: DragGesture.Value) {
        if drag == nil || drag?.landing == true {
            let visibleIDs = Set(visible.map(\.id))
            guard let hit = frames.first(where: { entry in
                visibleIDs.contains(entry.key) && entry.value.contains(value.startLocation)
            }) else { return }
            drag = ExtensionDrag(id: hit.key, origin: hit.value)
            showingOverflow = false
        }
        drag?.translation = value.translation
        guard let carriedCentreX, !isOverOverflow else { return }
        reorder(around: carriedCentreX)
    }

    private func dragEnded(_ value: DragGesture.Value) {
        guard let drag, !drag.landing else { return }
        let id = drag.id

        if isOverOverflow {
            manager.setPinned(false, id: id)
            frames[id] = nil
            self.drag = nil
            return
        }

        withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
            self.drag?.landing = true
        }
        Task {
            try? await Task.sleep(for: .milliseconds(240))
            if self.drag?.id == id, self.drag?.landing == true {
                self.drag = nil
            }
        }
    }

    private func reorder(around x: CGFloat) {
        guard let drag else { return }
        let visibleIDs = Set(visible.map(\.id))
        guard let hit = frames.first(where: { entry in
            entry.key != drag.id && visibleIDs.contains(entry.key)
                && entry.value.minX <= x && x < entry.value.maxX
        }) else { return }

        let relative = (x - hit.value.minX) / max(hit.value.width, 1)
        place(drag.id, before: relative < 0.5, of: hit.key)
    }

    private func place(_ id: String, before: Bool, of anchor: String) {
        let order = pinned.map(\.id)
        guard let anchorIndex = order.firstIndex(of: anchor) else { return }
        let current = order.firstIndex(of: id)
        if before, current == anchorIndex - 1 {
            return
        }
        if !before, current == anchorIndex + 1 {
            return
        }

        let target: String? = before
            ? anchor
            : (anchorIndex + 1 < order.count ? order[anchorIndex + 1] : nil)
        guard target != id else { return }
        manager.move(id, before: target)
    }
}

struct ExtensionArtwork: View {
    let manager: ExtensionManager
    let record: InstalledExtension
    var size: CGFloat = 16

    var body: some View {
        _ = manager.actionRevision
        return Group {
            if let icon = manager.action(for: record.id)?
                .icon(for: CGSize(width: size, height: size)) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: size * 0.75, weight: .semibold))
            }
        }
        .frame(width: size, height: size)
    }
}

struct ExtensionActionButton: View {
    let manager: ExtensionManager
    let browser: BrowserModel
    let record: InstalledExtension
    let isLifted: Bool

    @State private var hovering = false

    private var action: WKWebExtension.Action? {
        _ = manager.actionRevision
        return manager.action(for: record.id)
    }

    private var badge: String {
        action?.badgeText ?? ""
    }

    var body: some View {
        let action = action
        ExtensionArtwork(manager: manager, record: record)
            .frame(width: 30, height: 28)
            .overlay(alignment: .bottomTrailing) {
                if !badge.isEmpty {
                    Text(verbatim: badge)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Theme.accent, in: Capsule())
                        .padding(.trailing, 1)
                }
            }
            .hoverBackground(isActive: hovering)
            .opacity(isLifted ? 0 : (action?.isEnabled == false ? 0.4 : 1))
            .onTapGesture { manager.performAction(for: record.id) }
            .onHover { hovering = $0 }
            .animation(Theme.Motion.quick, value: hovering)
            .help(action?.label ?? record.displayName)
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(action?.label ?? record.displayName)
            .accessibilityAction { manager.performAction(for: record.id) }
            .background { PopupAnchor(manager: manager, extensionID: record.id) }
    }
}

struct ExtensionOverflowButton: View {
    let manager: ExtensionManager
    let records: [InstalledExtension]
    let collapsedCount: Int
    let isArmed: Bool
    @Binding var isPresented: Bool

    @State private var hovering = false
    @Environment(\.chromeIsLight) private var chromeIsLight

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 11.5, weight: .semibold))
                .frame(width: 30, height: 28)
                .overlay(alignment: .bottomTrailing) { marker }
                .hoverBackground(isActive: hovering || isPresented)
                .overlay {
                    if isArmed {
                        Circle()
                            .strokeBorder(Theme.accent, lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            ChromeInk.glyph(onLight: chromeIsLight, hovering: hovering || isPresented)
        )
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .help(Text(helpText))
        .background { OverflowAnchor(manager: manager) }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ExtensionOverflowList(
                manager: manager,
                records: records,
                collapsedCount: collapsedCount,
                isPresented: $isPresented
            )
        }
    }

    @ViewBuilder
    private var marker: some View {
        if collapsedCount > 0 {
            dot(Theme.warning)
        } else if hasBadge {
            dot(Theme.accent)
        }
    }

    private func dot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 4, height: 4)
            .padding(.trailing, 6)
            .padding(.bottom, 5)
    }

    private var hasBadge: Bool {
        _ = manager.actionRevision
        return records.contains { !(manager.action(for: $0.id)?.badgeText ?? "").isEmpty }
    }

    private var helpText: LocalizedStringResource {
        collapsedCount > 0
            ? "More Extensions — \(collapsedCount) don’t fit in this window"
            : "More Extensions"
    }
}

private struct ExtensionOverflowList: View {
    let manager: ExtensionManager
    let records: [InstalledExtension]
    let collapsedCount: Int
    @Binding var isPresented: Bool

    static let inset: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(records.enumerated(), id: \.element.id) { position, record in
                ExtensionOverflowRow(
                    manager: manager,
                    record: record,
                    isCollapsedByWidth: position < collapsedCount,
                    isPresented: $isPresented
                )
            }
        }
        .padding(Self.inset)
        .frame(width: 236)
        .environment(\.colorScheme, macScheme)
    }

    private var macScheme: ColorScheme {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }
}

private struct ExtensionOverflowRow: View {
    let manager: ExtensionManager
    let record: InstalledExtension
    let isCollapsedByWidth: Bool
    @Binding var isPresented: Bool

    @State private var hovering = false
    @State private var pinHovering = false
    @Environment(\.chromeWash) private var wash

    var body: some View {
        HStack(spacing: 9) {
            HStack(spacing: 9) {
                ExtensionArtwork(manager: manager, record: record)
                Text(verbatim: record.displayName)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: run)
            .onHover { hovering = $0 }

            trailing
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .hoverBackground(
            isActive: hovering,
            in: RoundedRectangle(cornerRadius: Self.rowRadius, style: .continuous)
        )
        .animation(Theme.Motion.quick, value: hovering)
    }

    static var rowRadius: CGFloat {
        Theme.Radius.nested(
            in: Theme.Radius.window,
            inset: ExtensionOverflowList.inset
        )
    }

    @ViewBuilder
    private var trailing: some View {
        if isCollapsedByWidth {
            Text("No room")
                .font(Theme.Font.label)
                .foregroundStyle(.tertiary)
        } else {
            Button {
                manager.setPinned(true, id: record.id)
                isPresented = false
            } label: {
                Text("Pin")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        pinHovering ? wash.layer(0.12) : wash.layer(0.10),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .onHover { pinHovering = $0 }
            .animation(Theme.Motion.quick, value: pinHovering)
            .help("Show \(record.displayName) on the toolbar")
        }
    }

    private func run() {
        isPresented = false
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            manager.performAction(for: record.id)
        }
    }
}

private struct OverflowAnchor: NSViewRepresentable {
    let manager: ExtensionManager

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        manager.registerOverflowAnchor(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        manager.registerOverflowAnchor(nsView)
    }
}

struct PopupAnchor: NSViewRepresentable {
    let manager: ExtensionManager
    let extensionID: String

    func makeNSView(context: Context) -> ExtensionAnchorView {
        let view = ExtensionAnchorView()
        view.manager = manager
        view.extensionID = extensionID
        manager.registerAnchor(view, for: extensionID)
        return view
    }

    func updateNSView(_ nsView: ExtensionAnchorView, context: Context) {}
}

final class ExtensionAnchorView: NSView {
    weak var manager: ExtensionManager?
    var extensionID = ""

    override func hitTest(_ point: NSPoint) -> NSView? {
        SecondaryClick.matches(NSApp.currentEvent) ? super.hitTest(point) : nil
    }

    override func rightMouseDown(with event: NSEvent) {
        SecondaryClick.present(manager?.contextMenu(for: extensionID), with: event, in: self)
    }

    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.control) else {
            super.mouseDown(with: event)
            return
        }
        SecondaryClick.present(manager?.contextMenu(for: extensionID), with: event, in: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        manager?.contextMenu(for: extensionID)
    }
}

enum SecondaryClick {
    static func matches(_ event: NSEvent?) -> Bool {
        guard let event else { return false }
        switch event.type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return true
        case .leftMouseDown, .leftMouseUp:
            return event.modifierFlags.contains(.control)
        default:
            return false
        }
    }

    static func present(_ menu: NSMenu?, with event: NSEvent, in view: NSView) {
        guard let menu, !menu.items.isEmpty else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }
}

struct ClusterMenuCatcher: NSViewRepresentable {
    let extensionID: (CGFloat) -> String?
    let menuForExtension: (String) -> NSMenu?

    func makeNSView(context: Context) -> ClusterMenuView {
        let view = ClusterMenuView()
        view.extensionID = extensionID
        view.menuForExtension = menuForExtension
        return view
    }

    func updateNSView(_ nsView: ClusterMenuView, context: Context) {
        nsView.extensionID = extensionID
        nsView.menuForExtension = menuForExtension
    }
}

final class ClusterMenuView: NSView {
    var extensionID: ((CGFloat) -> String?)?
    var menuForExtension: ((String) -> NSMenu?)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        SecondaryClick.matches(NSApp.currentEvent) ? super.hitTest(point) : nil
    }

    override func rightMouseDown(with event: NSEvent) {
        present(event)
    }

    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.control) else {
            super.mouseDown(with: event)
            return
        }
        present(event)
    }

    private func present(_ event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        guard let id = extensionID?(x) else { return }
        SecondaryClick.present(menuForExtension?(id), with: event, in: self)
    }
}

struct StoreInstallButton: View {
    let manager: ExtensionManager
    let browser: BrowserModel

    @State private var hovering = false

    private var storeID: String? {
        ChromeWebStore.extensionID(fromPageURL: browser.activeTab?.urlString ?? "")
    }

    var body: some View {
        if let id = storeID {
            content(for: id)
                .transition(.opacity)
                .animation(Theme.Motion.settle, value: manager.installState)
        }
    }

    @ViewBuilder
    private func content(for id: String) -> some View {
        switch manager.installState {
        case .installing(let installing) where installing == id:
            label(symbol: nil, text: "Installing…", tint: .secondary, spinning: true)
        case .failed(let failed, let message) where failed == id:
            Button { Task { await manager.install(fromStoreID: id) } } label: {
                label(symbol: "exclamationmark.triangle.fill", text: "Retry", tint: .orange)
            }
            .buttonStyle(.plain)
            .help(message)
        default:
            if manager.isInstalled(id) {
                label(symbol: "checkmark", text: "Installed", tint: .secondary)
                    .help("Already installed in Linen")
            } else {
                Button { Task { await manager.install(fromStoreID: id) } } label: {
                    label(symbol: "arrow.down.circle.fill", text: "Install", tint: Theme.accent)
                }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
                .help("Install this extension in Linen")
            }
        }
    }

    private func label(
        symbol: String?,
        text: LocalizedStringResource,
        tint: Color,
        spinning: Bool = false
    ) -> some View {
        HStack(spacing: 4) {
            if spinning {
                Spinner(size: 11)
            } else if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10.5, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(Theme.Wash.hairline, in: Capsule())
        .hoverBackground(isActive: hovering, tint: tint, in: Capsule())
        .contentShape(Capsule())
        .animation(Theme.Motion.quick, value: hovering)
    }
}
