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
            tab?.reload()
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
            menu.addItem(title: label(for: item, coordinator: coordinator), image: icon(for: item)) { [weak tab] in
                tab?.webView.go(to: item)
            }
        }
        menu.addItem(.separator())
        menu.addItem(title: "Show All History", image: symbol("clock.arrow.circlepath"), key: "y") { [weak coordinator] in
            coordinator?.openPalette()
        }
        return menu
    }

    private static func label(for item: WKBackForwardListItem, coordinator: AppCoordinator) -> String {
        if let page = BrowserTab.InternalPage(url: item.url) {
            guard let title = SettingsPageTitles.title(of: item.url, coordinator: coordinator) else {
                return page.title
            }
            return "\(page.title) — \(title)"
        }
        if SystemPages.isStart(item.url) {
            return SystemPages.startTitle
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
            return symbol(SystemPages.startSymbol)
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

@MainActor
enum TabsHoldMenu {
    static func menu(browser: BrowserModel, coordinator: AppCoordinator) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(title: String(localized: "New Tab"), image: symbol("plus"), key: "t") { [weak coordinator] in
            coordinator?.requestNewTab()
        }
        menu.addItem(title: String(localized: "New Folder"), image: symbol("folder.badge.plus")) { [weak browser, weak coordinator] in
            browser?.createFolder()
            coordinator?.overlays.isTabListOpen = true
        }
        if browser.canReopenClosedTab {
            menu.addItem(
                title: String(localized: "Reopen Last Closed Tab"),
                image: symbol("arrow.uturn.backward"),
                key: "t",
                modifiers: [.command, .shift]
            ) { [weak browser] in
                browser?.reopenLastClosedTab()
            }
        }
        menu.addItem(title: String(localized: "Search Everything…"), image: symbol("magnifyingglass"), key: "k") { [weak coordinator] in
            coordinator?.openPalette()
        }

        guard let tab = browser.activeTab else { return menu }
        menu.addItem(.separator())
        menu.addItem(
            title: String(localized: "Duplicate Tab"),
            image: symbol("plus.square.on.square"),
            key: "d",
            modifiers: [.command, .shift]
        ) { [weak browser, weak tab] in
            guard let browser, let tab else { return }
            browser.duplicate(tab)
        }
        menu.addItem(
            title: tab.isShowingPin ? String(localized: "Unpin Tab") : String(localized: "Pin Tab"),
            image: symbol(tab.isShowingPin ? "pin.slash" : "pin"),
            key: "d"
        ) { [weak coordinator] in
            coordinator?.togglePin()
        }

        menu.addItem(.separator())
        menu.addItem(title: String(localized: "Close Tab"), image: symbol("xmark"), key: "w") { [weak coordinator] in
            coordinator?.closeActiveTabAskingIfPinned()
        }
        if browser.tabs.count > 1 {
            menu.addItem(title: String(localized: "Close Other Tabs"), image: symbol("xmark.square")) { [weak browser, weak tab] in
                guard let browser, let tab else { return }
                let count = browser.tabs.count - 1
                Task {
                    guard await ConfirmAlert.destructive(
                        "Close \(count) tabs?",
                        verb: "Close Tabs"
                    ) else { return }
                    browser.closeOthers(tab)
                }
            }
        }
        return menu
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
            menu.popUp(positioning: nil, at: menuOrigin(for: menu.size), in: self)
        }

        private func menuOrigin(for size: NSSize) -> NSPoint {
            let gap: CGFloat = 4
            let frame = convert(bounds, to: nil)
            var fitsBelow = true
            if let window, let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
                fitsBelow = window.convertToScreen(frame).minY - gap - size.height >= visible.minY
            }
            let origin = NSPoint(x: frame.minX, y: fitsBelow ? frame.minY - gap : frame.maxY + gap + size.height)
            return convert(origin, from: nil)
        }
    }
}
