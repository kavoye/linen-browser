// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import WebKit

extension ExtensionManager {
    var windowAdapters: [ExtensionWindowAdapter] {
        windowOrder.compactMap { windows[$0] }.filter { $0.browser != nil }
    }

    var focusedWindowAdapter: ExtensionWindowAdapter? {
        windowAdapters.first { $0.nativeWindow?.isKeyWindow == true }
    }

    var preferredWindowAdapter: ExtensionWindowAdapter? {
        focusedWindowAdapter ?? lastFocusedWindow ?? windowAdapters.first
    }

    func registeredWindow(in browser: BrowserModel?) -> ExtensionWindowAdapter? {
        if let browser {
            return liveWindow(for: browser)
        }
        return preferredWindowAdapter
    }

    private func liveWindow(for browser: BrowserModel) -> ExtensionWindowAdapter? {
        let identifier = ObjectIdentifier(browser)
        guard let window = windows[identifier] else { return nil }
        guard window.browser === browser else {
            windows[identifier] = nil
            windowOrder.removeAll { $0 == identifier }
            return nil
        }
        return window
    }

    func owns(_ window: ExtensionWindowAdapter) -> Bool {
        guard let browser = window.browser else { return false }
        return windows[ObjectIdentifier(browser)] === window
    }

    func action(for id: String, in browser: BrowserModel? = nil) -> WKWebExtension.Action? {
        guard let window = registeredWindow(in: browser), let context = contexts[id] else { return nil }
        let tab = window.browser?.activeTab.map { adapter(for: $0) }
        return context.action(for: tab)
    }

    func hasOptionsPage(id: String) -> Bool {
        contexts[id]?.optionsPageURL != nil
    }

    func openOptionsPage(id: String) {
        guard let url = contexts[id]?.optionsPageURL else { return }
        _ = openTab(url)
    }

    @discardableResult
    func register(browser: BrowserModel, window: NSWindow? = nil) -> ExtensionWindowAdapter {
        let identifier = ObjectIdentifier(browser)
        if let existing = liveWindow(for: browser) {
            if let window {
                existing.nativeWindow = window
            }
            return existing
        }
        let adapter = ExtensionWindowAdapter(browser: browser, manager: self, window: window)
        windows[identifier] = adapter
        windowOrder.append(identifier)
        browser.extensionPageHost = { [weak self, weak adapter] url in
            guard let self, let adapter, owns(adapter),
                  let context = controller.extensionContext(for: url),
                  let configuration = context.webViewConfiguration else { return nil }
            let webExtension = context.webExtension
            return ExtensionPageHost(
                configuration: configuration,
                baseURL: context.baseURL,
                name: webExtension.displayName ?? String(localized: "Extension"),
                icon: webExtension.icon(for: CGSize(width: 32, height: 32))
            )
        }
        browser.onTabOpened = { [weak self, weak adapter] tab in
            guard let self, let adapter, owns(adapter) else { return }
            controller.didOpenTab(self.adapter(for: tab))
        }
        browser.onTabClosed = { [weak self, weak adapter] tab in
            guard let self, let adapter, owns(adapter),
                  let closed = tabAdapters.removeValue(forKey: tab.id) else { return }
            controller.didCloseTab(closed, windowIsClosing: false)
            closed.invalidate()
        }
        browser.onActiveTabChanged = { [weak self, weak adapter] newTab, previousTab in
            guard let self, let adapter, owns(adapter), let newTab else { return }
            let previous = previousTab.flatMap { tabAdapters[$0.id] }
            controller.didActivateTab(self.adapter(for: newTab), previousActiveTab: previous)
        }
        browser.onTabTransferredIn = { [weak self, weak adapter] tab, source, oldIndex in
            guard let self, let adapter, owns(adapter), let browser = adapter.browser else { return }
            didMove(tab: tab, from: source, to: browser, oldIndex: oldIndex)
        }
        browser.onNavigationStarted = { [weak self, weak adapter] _, url in
            guard let self, let adapter, owns(adapter) else { return }
            wakeBackgrounds(for: url)
        }
        if hasStarted {
            controller.didOpenWindow(adapter)
        }
        return adapter
    }

    func unregister(browser: BrowserModel) {
        let identifier = ObjectIdentifier(browser)
        guard let window = liveWindow(for: browser) else { return }
        for tab in browser.tabs {
            _ = adapter(for: tab)
        }
        let closingTabs = tabAdapters.values.filter { $0.browser === browser }
        for tabAdapter in closingTabs {
            controller.didCloseTab(tabAdapter, windowIsClosing: true)
        }
        controller.didCloseWindow(window)
        windows[identifier] = nil
        windowOrder.removeAll { $0 == identifier }
        if lastFocusedWindow === window {
            lastFocusedWindow = nil
        }
        browser.extensionPageHost = nil
        browser.onTabOpened = nil
        browser.onTabClosed = nil
        browser.onActiveTabChanged = nil
        browser.onNavigationStarted = nil
        browser.onTabTransferredIn = nil
        for tabAdapter in closingTabs {
            if let tab = tabAdapter.tab {
                tabAdapters[tab.id] = nil
            }
            tabAdapter.invalidate()
        }
        window.invalidate()
        didUnregister(browser: browser, window: window)
    }

    func focus(browser: BrowserModel?) {
        let window = browser.flatMap { liveWindow(for: $0) }
        if let window {
            lastFocusedWindow = window
        }
        controller.didFocusWindow(window)
        noteActionUpdate()
    }

    func adapter(for browser: BrowserModel) -> ExtensionWindowAdapter? {
        liveWindow(for: browser)
    }

    func didMove(tab: BrowserTab, from source: BrowserModel, to destination: BrowserModel, oldIndex: Int) {
        guard let previousWindow = adapter(for: source), let newWindow = adapter(for: destination),
              destination.tabs.contains(where: { $0 === tab }) else { return }
        let adapter = tabAdapters[tab.id] ?? ExtensionTabAdapter(tab: tab, browser: source, windowAdapter: previousWindow)
        tabAdapters[tab.id] = adapter
        adapter.move(to: destination, window: newWindow)
        controller.didMoveTab(adapter, from: oldIndex, in: previousWindow)
    }

    @discardableResult
    func openTab(_ url: URL?, in browser: BrowserModel? = nil) -> BrowserTab? {
        registeredWindow(in: browser)?.browser?.newTab(url: url)
    }

    func adapter(for tab: BrowserTab) -> ExtensionTabAdapter {
        if let existing = tabAdapters[tab.id] {
            return existing
        }
        guard let window = windowAdapters.first(where: { window in
            window.browser?.tabs.contains(where: { $0 === tab }) == true
        }), let browser = window.browser else {
            preconditionFailure("Extension tabs must belong to a registered browser window")
        }
        let adapter = ExtensionTabAdapter(tab: tab, browser: browser, windowAdapter: window)
        tabAdapters[tab.id] = adapter
        return adapter
    }

}
