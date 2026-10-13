// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import WebKit

@MainActor
final class ExtensionTabAdapter: NSObject, WKWebExtensionTab {
    private(set) weak var tab: BrowserTab?
    private(set) weak var browser: BrowserModel?
    private weak var windowAdapter: ExtensionWindowAdapter?

    init(tab: BrowserTab, browser: BrowserModel, windowAdapter: ExtensionWindowAdapter) {
        self.tab = tab
        self.browser = browser
        self.windowAdapter = windowAdapter
    }

    func move(to browser: BrowserModel, window: ExtensionWindowAdapter) {
        self.browser = browser
        windowAdapter = window
    }

    func invalidate() {
        tab = nil
        browser = nil
        windowAdapter = nil
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
        guard let tab, let browser else { completionHandler(ExtensionWindowError.unavailable); return }
        browser.activate(tab)
        completionHandler(nil)
    }

    func close(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        guard let tab, let browser else { completionHandler(ExtensionWindowError.unavailable); return }
        browser.close(tab)
        completionHandler(nil)
    }
}

enum ExtensionWindowError: LocalizedError {
    case unavailable
    case creationFailed
    case foreignTab

    var errorDescription: String? {
        switch self {
        case .unavailable:
            String(localized: "The browser window is no longer available.")
        case .creationFailed:
            String(localized: "The browser could not create the requested window.")
        case .foreignTab:
            String(localized: "Tabs cannot move between profiles or private sessions.")
        }
    }
}

@MainActor
final class ExtensionWindowAdapter: NSObject, WKWebExtensionWindow {
    private(set) weak var browser: BrowserModel?
    private weak var manager: ExtensionManager?
    weak var nativeWindow: NSWindow?

    init(browser: BrowserModel, manager: ExtensionManager, window: NSWindow? = nil) {
        self.browser = browser
        self.manager = manager
        nativeWindow = window
    }

    func invalidate() {
        browser = nil
        manager = nil
        nativeWindow = nil
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
        guard let window = nativeWindow else { return .normal }
        if window.styleMask.contains(.fullScreen) {
            return .fullscreen
        }
        if window.isMiniaturized {
            return .minimized
        }
        if window.isZoomed {
            return .maximized
        }
        return .normal
    }

    func setWindowState(
        _ state: WKWebExtension.WindowState,
        for context: WKWebExtensionContext,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        guard nativeWindow != nil else { completionHandler(ExtensionWindowError.unavailable); return }
        apply(state: state)
        completionHandler(nil)
    }

    private func apply(state: WKWebExtension.WindowState) {
        guard let window = nativeWindow else { return }
        if window.styleMask.contains(.fullScreen) != (state == .fullscreen) {
            window.toggleFullScreen(nil)
        }
        if state == .minimized {
            window.miniaturize(nil)
        } else {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            if state != .fullscreen, window.isZoomed != (state == .maximized) {
                window.zoom(nil)
            }
        }
    }

    func apply(configuration: WKWebExtension.WindowConfiguration) {
        guard let window = nativeWindow else { return }
        let proposed = configuration.frame
        var frame = window.frame
        if proposed.origin.x.isFinite {
            frame.origin.x = proposed.origin.x
        }
        if proposed.origin.y.isFinite {
            frame.origin.y = proposed.origin.y
        }
        if proposed.width.isFinite, proposed.width > 0 {
            frame.size.width = proposed.width
        }
        if proposed.height.isFinite, proposed.height > 0 {
            frame.size.height = proposed.height
        }
        window.setFrame(frame, display: true)
        apply(state: configuration.windowState)
        if configuration.shouldBeFocused {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func isPrivate(for context: WKWebExtensionContext) -> Bool {
        manager?.profile?.isPrivate ?? false
    }

    func frame(for context: WKWebExtensionContext) -> CGRect {
        nativeWindow?.frame ?? .null
    }

    func setFrame(
        _ frame: CGRect,
        for context: WKWebExtensionContext,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        guard let nativeWindow else { completionHandler(ExtensionWindowError.unavailable); return }
        nativeWindow.setFrame(frame, display: true)
        completionHandler(nil)
    }

    func screenFrame(for context: WKWebExtensionContext) -> CGRect {
        nativeWindow?.screen?.frame ?? .null
    }

    func focus(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        guard let window = nativeWindow else { completionHandler(ExtensionWindowError.unavailable); return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        if let browser {
            manager?.focus(browser: browser)
        }
        completionHandler(nil)
    }

    func close(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        guard let window = nativeWindow else { completionHandler(ExtensionWindowError.unavailable); return }
        window.performClose(nil)
        completionHandler(nil)
    }
}
