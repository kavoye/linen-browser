// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import WebKit

@MainActor
final class ExtensionTabAdapter: NSObject, WKWebExtensionTab {
    private(set) weak var tab: BrowserTab?
    private weak var browser: BrowserModel?
    private weak var windowAdapter: ExtensionWindowAdapter?

    init(tab: BrowserTab, browser: BrowserModel, windowAdapter: ExtensionWindowAdapter) {
        self.tab = tab
        self.browser = browser
        self.windowAdapter = windowAdapter
    }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        windowAdapter
    }

    func indexInWindow(for context: WKWebExtensionContext) -> Int {
        guard let tab, let index = browser?.tabs.firstIndex(where: { $0 === tab }) else {
            return NSNotFound
        }
        return index
    }

    func webView(for context: WKWebExtensionContext) -> WKWebView? {
        tab?.webView
    }

    func isSelected(for context: WKWebExtensionContext) -> Bool {
        guard let tab else { return false }
        return browser?.activeTabID == tab.id
    }

    func activate(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        if let tab {
            browser?.activate(tab)
        }
        completionHandler(nil)
    }

    func close(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        if let tab {
            browser?.close(tab)
        }
        completionHandler(nil)
    }
}

@MainActor
final class ExtensionWindowAdapter: NSObject, WKWebExtensionWindow {
    private weak var browser: BrowserModel?
    private weak var manager: ExtensionManager?

    init(browser: BrowserModel, manager: ExtensionManager) {
        self.browser = browser
        self.manager = manager
    }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        guard let browser, let manager else { return [] }
        return browser.tabs.map { manager.adapter(for: $0) }
    }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        guard let browser, let manager, let active = browser.activeTab else { return nil }
        return manager.adapter(for: active)
    }

    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType {
        .normal
    }

    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState {
        .normal
    }

    func isPrivate(for context: WKWebExtensionContext) -> Bool {
        false
    }

    func frame(for context: WKWebExtensionContext) -> CGRect {
        NSApp.mainWindow?.frame ?? NSApp.keyWindow?.frame ?? .null
    }

    func screenFrame(for context: WKWebExtensionContext) -> CGRect {
        NSScreen.main?.frame ?? .null
    }

    func focus(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        completionHandler(nil)
    }
}
