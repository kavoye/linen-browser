// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit

extension AppCoordinator {
    @discardableResult
    func moveTab(_ tab: BrowserTab, to destination: AppCoordinator) -> Bool {
        guard !isClosed, !destination.isClosed,
              destination.browser.adoptTab(tab, from: browser) else { return false }
        destination.showBrowser()
        return true
    }

    func moveTabToNewWindow(_ tab: BrowserTab) {
        // Private windows have independent cookie stores. Moving a live page
        // between those stores would also move its authenticated session.
        guard !profiles.isPrivate, let application else { return }
        let destination = application.newWindow(profile: profiles.current)
        let placeholder = destination.browser.activeTab
        if moveTab(tab, to: destination), let placeholder {
            destination.browser.close(placeholder, recordForReopening: false)
        }
    }

    @discardableResult
    func finishWindowDrag(_ items: [SidebarItem], at screenPoint: NSPoint) -> AppCoordinator? {
        guard let sourceWindow = nativeWindow, !sourceWindow.frame.contains(screenPoint),
              !profiles.isPrivate, let application
        else { return nil }
        let ids = browser.sidebarTree.expanded(Set(items)).compactMap { item -> UUID? in
            guard case .tab(let id) = item else { return nil }
            return id
        }
        let tabs = browser.tabs.filter { ids.contains($0.id) }
        guard !tabs.isEmpty else { return nil }
        let target = windowDragTarget(at: screenPoint)
        if let target, target.browser.context !== browser.context {
            return nil
        }
        let destination = target ?? application.newWindow(profile: profiles.current)
        let placeholder = target == nil ? destination.browser.activeTab : nil
        let drop = target?.sidebarDrag.incoming.flatMap { drop -> SidebarIncomingDrop? in
            let browser = destination.browser
            guard drop.parent.map({ browser.folder(id: $0) != nil }) ?? true,
                  drop.before.map({ browser.sidebarTree.rows(in: drop.parent).contains($0) }) ?? true
            else { return nil }
            return drop
        }
        let pinned = drop.map { drop in
            drop.parent.map { destination.browser.isKept(.folder($0)) }
                ?? drop.before.map { destination.browser.isKept($0) }
                ?? false
        }
        for tab in tabs {
            _ = destination.browser.adoptTab(tab, from: browser)
        }
        if let drop, drop.isAimed, let pinned {
            let moved = tabs.filter { destination.browser.tab(id: $0.id) != nil }.map { SidebarItem.tab($0.id) }
            destination.browser.move(
                moved,
                into: drop.parent.flatMap(destination.browser.folder(id:)),
                before: drop.before,
                settlingPins: false
            )
            destination.browser.setPinned(pinned, for: moved)
        }
        if let placeholder {
            destination.browser.close(placeholder, recordForReopening: false)
        }
        if target == nil, let window = destination.nativeWindow {
            window.setFrameTopLeftPoint(NSPoint(x: screenPoint.x - 100, y: screenPoint.y + 20))
        }
        destination.showBrowser()
        return destination
    }

    @discardableResult
    func aimWindowDrag(at screenPoint: NSPoint?) -> Bool {
        let hovered = screenPoint.flatMap(windowDragTarget(at:))
        let target = hovered.flatMap { $0.browser.context === browser.context ? $0 : nil }
        for window in application?.windows ?? [] {
            var incoming: SidebarIncomingDrop?
            if window === target, let screenPoint, let native = window.nativeWindow {
                incoming = window.sidebar.isShowing
                    ? window.sidebarDrag.incomingDrop(at: screenPoint, in: native, browser: window.browser)
                    : SidebarIncomingDrop()
            }
            if window.sidebarDrag.incoming != incoming {
                window.sidebarDrag.incoming = incoming
            }
        }
        return screenPoint != nil && hovered === target
    }

    private func windowDragTarget(at screenPoint: NSPoint) -> AppCoordinator? {
        guard let application else { return nil }
        return NSApp.orderedWindows.lazy
            .filter { $0.isVisible && !$0.isMiniaturized && $0.frame.contains(screenPoint) }
            .compactMap { window in application.windows.first { $0.nativeWindow === window } }
            .first { $0 !== self }
    }
}
