// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import WebKit

@MainActor
enum NavigationHoldMenu {
    private static let maximumEntries = 12

    private static let maximumTitleLength = 64

    static func back(for tab: BrowserTab, coordinator: AppCoordinator) -> NSMenu? {
        history(tab.backList.reversed(), tab: tab, coordinator: coordinator)
    }

    static func forward(for tab: BrowserTab, coordinator: AppCoordinator) -> NSMenu? {
        history(tab.webView.backForwardList.forwardList, tab: tab, coordinator: coordinator)
    }

    static func reload(for tab: BrowserTab) -> NSMenu? {
        guard !tab.isLoading else { return nil }
        let menu = NSMenu()
        menu.addItem(title: "Reload Page", image: symbol("arrow.clockwise"), key: "r") { [weak tab] in
            tab?.webView.reload()
        }
        menu.addItem(
            title: "Reload Page from Origin",
            image: symbol("arrow.2.circlepath"),
            key: "r",
            modifiers: [.command, .shift]
        ) { [weak tab] in
            tab?.webView.reloadFromOrigin()
        }
        return menu
    }

    private static func history(
        _ items: [WKBackForwardListItem],
        tab: BrowserTab,
        coordinator: AppCoordinator
    ) -> NSMenu? {
        guard !items.isEmpty else { return nil }
        let menu = NSMenu()
        for item in items.prefix(maximumEntries) {
            menu.addItem(title: label(for: item), image: icon(for: item)) { [weak tab] in
                tab?.webView.go(to: item)
            }
        }
        menu.addItem(.separator())
        menu.addItem(title: "Show All History", image: symbol("clock.arrow.circlepath"), key: "y") { [weak coordinator] in
            coordinator?.openPalette()
        }
        return menu
    }

    private static func label(for item: WKBackForwardListItem) -> String {
        if let page = BrowserTab.InternalPage(url: item.url) {
            guard let category = SystemPages.settingsCategory(of: item.url) else {
                return page.title
            }
            return "\(page.title) — \(String(localized: category.title))"
        }
        if SystemPages.isStart(item.url) {
            return BrowserTab.placeholderTitle
        }
        var title = item.title ?? ""
        if title.isEmpty {
            title = item.url.displayHost ?? item.url.absoluteString
        }
        guard title.count > maximumTitleLength else { return title }
        return title.prefix(maximumTitleLength).trimmingCharacters(in: .whitespaces) + "…"
    }

    private static func icon(for item: WKBackForwardListItem) -> NSImage? {
        if let page = BrowserTab.InternalPage(url: item.url) {
            return symbol(page.symbol)
        }
        if SystemPages.isStart(item.url) {
            return symbol("square.grid.2x2")
        }
        guard let host = item.url.host(),
              let cached = FaviconLoader.shared.cached(for: host),
              let sized = cached.copy() as? NSImage
        else { return symbol("globe") }
        sized.size = NSSize(width: 16, height: 16)
        return sized
    }

    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }
}

private final class MenuHandler: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func fire() {
        handler()
    }
}

extension NSMenu {
    func addItem(
        title: String,
        image: NSImage? = nil,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = .command,
        handler: @escaping () -> Void
    ) {
        let target = MenuHandler(handler)
        let item = NSMenuItem(title: title, action: #selector(MenuHandler.fire), keyEquivalent: key)
        item.image = image
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        item.representedObject = target
        addItem(item)
    }
}

struct ToolbarHoldCatcher: NSViewRepresentable {
    static let holdDelay: Duration = .milliseconds(400)

    @Binding var hovering: Bool
    let menu: () -> NSMenu?
    let action: () -> Void

    func makeNSView(context: Context) -> HoldCatcherView {
        let view = HoldCatcherView()
        view.onHover = { hovering = $0 }
        view.menuProvider = menu
        view.action = action
        return view
    }

    func updateNSView(_ nsView: HoldCatcherView, context: Context) {
        nsView.onHover = { hovering = $0 }
        nsView.menuProvider = menu
        nsView.action = action
    }

    final class HoldCatcherView: NSView {
        var onHover: (Bool) -> Void = { _ in }
        var menuProvider: (() -> NSMenu?)?
        var action: () -> Void = {}

        private var holdTask: Task<Void, Never>?
        private var menuTookOver = false

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                owner: self
            ))
        }

        override func mouseEntered(with event: NSEvent) {
            onHover(true)
        }

        override func mouseExited(with event: NSEvent) {
            onHover(false)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override var mouseDownCanMoveWindow: Bool {
            false
        }

        override func mouseDown(with event: NSEvent) {
            menuTookOver = false
            let delay = ToolbarHoldCatcher.holdDelay
            holdTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.presentMenu()
            }
        }

        override func mouseUp(with event: NSEvent) {
            holdTask?.cancel()
            holdTask = nil
            guard !menuTookOver else { return }
            guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
            action()
        }

        override func rightMouseDown(with event: NSEvent) {
            presentMenu()
        }

        private func presentMenu() {
            holdTask?.cancel()
            holdTask = nil
            guard let menu = menuProvider?(), menu.numberOfItems > 0 else { return }
            menuTookOver = true
            onHover(false)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: self)
        }
    }
}
