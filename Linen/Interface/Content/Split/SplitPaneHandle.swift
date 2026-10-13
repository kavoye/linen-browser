// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import QuartzCore
import SwiftUI

nonisolated enum SplitPillVisibility {
    static let resting: Double = 0.35
    static let settleDelay = Duration.seconds(1.2)
    static let settleFade = 0.8

    static func isEngaged(isHidden: Bool, isHovered: Bool, isDragging: Bool, isSettled: Bool) -> Bool {
        !isHidden && (isHovered || isDragging || !isSettled)
    }

    static func opacity(isHidden: Bool, isHovered: Bool, isDragging: Bool, isSettled: Bool) -> Double {
        if isHidden {
            return 0
        }
        return isEngaged(
            isHidden: isHidden,
            isHovered: isHovered,
            isDragging: isDragging,
            isSettled: isSettled
        ) ? 1 : resting
    }
}

struct PaneHandle: View {
    let tab: BrowserTab
    let browser: BrowserModel
    let coordinator: AppCoordinator
    let isHidden: Bool
    let isFocused: Bool

    static let size = CGSize(width: 48, height: 16)

    @State private var hovering = false
    @State private var dragging = false
    @State private var settled = false

    private var model: SidebarDragModel {
        coordinator.sidebarDrag
    }

    private var split: TabSplit? {
        browser.splits.split(containing: tab.id)
    }

    private var dotInk: Color {
        if isFocused {
            return Color.white.opacity(0.8)
        }
        return hovering || dragging ? Theme.Wash.scrim : Theme.chrome(0.35)
    }

    private var visibility: Double {
        SplitPillVisibility.opacity(
            isHidden: isHidden,
            isHovered: hovering,
            isDragging: dragging,
            isSettled: settled
        )
    }

    private var wearsGlass: Bool {
        SplitPillVisibility.isEngaged(
            isHidden: isHidden,
            isHovered: hovering,
            isDragging: dragging,
            isSettled: settled
        )
    }

    var body: some View {
        ZStack {
            if isFocused, !wearsGlass {
                Capsule().fill(Theme.accent)
            }
            LoomPanelFill(
                shape: Capsule(),
                isVisible: wearsGlass,
                emphasis: isFocused ? 2.6 : 1,
                tint: isFocused ? Theme.accent : nil,
                isInteractive: true
            )
            .transaction { $0.animation = nil }
        }
        .overlay {
            Capsule().strokeBorder(Theme.Wash.strong, lineWidth: 0.5)
        }
        .overlay {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(dotInk)
                        .frame(width: 2.5, height: 2.5)
                }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .shadow(color: .black.opacity(wearsGlass ? 0 : 0.18), radius: 5, y: 2)
        .opacity(visibility)
        .contentShape(Capsule())
        .allowsHitTesting(!isHidden || dragging)
        .holdsWindowStillOnHover()
        .pointerStyle(dragging ? .grabActive : .grabIdle)
        .onHover { over in
            hovering = over
            if over {
                NSCursor.openHand.set()
            }
        }
        .onDisappear {
            if hovering || dragging {
                NSCursor.arrow.set()
            }
            guard dragging else { return }
            model.clearDrop()
            coordinator.movePane(tab, onto: nil, zone: .none, stayingOnThePage: true)
        }
        .gesture(drag)
        .onTapGesture { popUpMenu() }
        .contextMenu { menu }
        .help("Click for options · drag to move this page")
        .animation(Theme.Motion.quick, value: hovering)
        .animation(.easeOut(duration: SplitPillVisibility.settleFade), value: settled)
        .task {
            settled = false
            try? await Task.sleep(for: SplitPillVisibility.settleDelay)
            settled = true
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                model.panePointInWindow = value.location
                if !dragging {
                    dragging = true
                    model.source = .pane(tab.id)
                    coordinator.beginPaneDrag(tab)
                }
                if model.dropFrameInWindow.contains(value.location) {
                    model.aim(at: value.location)
                } else if model.target != nil {
                    model.target = nil
                }
            }
            .onEnded { value in
                let target = model.targetPaneID
                let zone = model.zone
                let landedOnThePage = model.contentFrameInWindow.contains(value.location)
                dragging = false
                NSCursor.arrow.set()
                model.clearDrop()
                coordinator.movePane(tab, onto: target, zone: zone, stayingOnThePage: landedOnThePage)
            }
    }

    private var canSwapRow: Bool {
        split?.sibling(of: tab.id) != nil
    }

    private func popUpMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let swap = menuItem(String(localized: "Swap Pages"), symbol: "arrow.left.arrow.right") {
            browser.swapSplitRow(containing: tab)
        }
        swap.isEnabled = canSwapRow
        menu.addItem(swap)

        if let axis = split?.axis {
            let title: String
            if axis == .stacked {
                title = String(localized: "Place Side by Side")
            } else {
                title = String(localized: "Stack Pages")
            }
            menu.addItem(menuItem(title, symbol: "rectangle.split.2x1") {
                browser.setSplitAxis(axis == .stacked ? .sideBySide : .stacked, containing: tab)
            })
        }
        menu.addItem(.separator())
        menu.addItem(menuItem(String(localized: "Remove This Page"), symbol: "rectangle.badge.minus") {
            browser.removeFromSplit(tab)
        })
        menu.addItem(menuItem(String(localized: "Exit Split"), symbol: "rectangle") {
            browser.dissolveSplit(containing: tab)
        })
        menu.addItem(.separator())
        menu.addItem(menuItem(String(localized: "Close This Page"), symbol: "xmark") {
            browser.close(tab)
        })
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func menuItem(_ title: String, symbol: String, action: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(PillMenuAction.fire), keyEquivalent: "")
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        let target = PillMenuAction(action)
        item.target = target
        item.representedObject = target
        return item
    }

    @ViewBuilder
    private var menu: some View {
        Button {
            browser.swapSplitRow(containing: tab)
        } label: {
            Label("Swap Pages", systemImage: "arrow.left.arrow.right")
        }
        .disabled(!canSwapRow)
        if let axis = split?.axis {
            Button {
                browser.setSplitAxis(axis == .stacked ? .sideBySide : .stacked, containing: tab)
            } label: {
                if axis == .stacked {
                    Label("Place Side by Side", systemImage: "rectangle.split.2x1")
                } else {
                    Label("Stack Pages", systemImage: "rectangle.split.2x1")
                }
            }
        }
        Divider()
        Button {
            browser.removeFromSplit(tab)
        } label: {
            Label("Remove This Page", systemImage: "rectangle.badge.minus")
        }
        Button {
            browser.dissolveSplit(containing: tab)
        } label: {
            Label("Exit Split", systemImage: "rectangle")
        }
        Divider()
        Button(role: .destructive) {
            browser.close(tab)
        } label: {
            Label("Close This Page", systemImage: "xmark")
        }
    }
}

private final class PillMenuAction: NSObject {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc func fire() {
        action()
    }
}

struct PaneEventCatcher: NSViewRepresentable {
    let onPointerDown: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onPointerDown = onPointerDown
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onPointerDown = onPointerDown
    }

    final class CatcherView: NSView {
        var onPointerDown: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard super.hitTest(point) != nil,
                  let event = window?.currentEvent ?? NSApp.currentEvent,
                  let onPointerDown
            else { return nil }
            switch event.type {
            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                Task { onPointerDown() }
            default:
                break
            }
            return nil
        }
    }
}
