// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import Testing

@testable import Linen

@MainActor
@Suite(.serialized)
struct SidebarRowControlTests {
    private struct Stage {
        let coordinator: AppCoordinator
        let window: NSWindow
        let host: NSView
        let tabs: [BrowserTab]

        var browser: BrowserModel {
            coordinator.browser
        }

        func settle() async throws {
            for _ in 0..<6 {
                try await Task.sleep(for: .milliseconds(20))
                window.layoutIfNeeded()
                window.displayIfNeeded()
            }
        }

        func send(_ type: NSEvent.EventType, at point: CGPoint) {
            let flipped = CGPoint(x: point.x, y: host.bounds.height - point.y)
            let event = NSEvent.mouseEvent(
                with: type, location: flipped, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                clickCount: type == .mouseMoved ? 0 : 1, pressure: type == .mouseMoved ? 0 : 1
            )!
            if type == .mouseMoved {
                host.mouseMoved(with: event)
            } else {
                window.sendEvent(event)
            }
        }

        func control(of tab: BrowserTab) throws -> CGPoint {
            let row = try #require(
                coordinator.sidebarDrag.frames.windowFrame(
                    of: .tab(tab.id),
                    listOrigin: coordinator.sidebarDrag.listOriginInWindow
                )
            )
            return CGPoint(x: row.maxX - SidebarMetrics.rowHeight / 2, y: row.midY)
        }

        func hover(_ point: CGPoint) async throws {
            let cursor = NSEvent.mouseLocation
            window.setFrameOrigin(CGPoint(x: cursor.x - point.x, y: cursor.y - (host.bounds.height - point.y)))
            try await settle()
            send(.mouseMoved, at: point)
            try await Task.sleep(for: .milliseconds(200))
            try await settle()
        }

        func close() {
            window.orderOut(nil)
            for tab in tabs where browser.tab(id: tab.id) != nil {
                browser.close(tab)
            }
        }
    }

    private func makeStage(pinning pinned: Int? = nil) async throws -> Stage {
        let coordinator = AppCoordinator()
        let browser = coordinator.browser
        var tabs: [BrowserTab] = []
        for index in 0..<8 {
            let tab = browser.newTab(activate: index == 0)
            tab.urlString = "https://site\(index).example/"
            tab.title = "Site \(index)"
            tabs.append(tab)
        }
        if let pinned {
            browser.setPinned(true, for: [.tab(tabs[pinned].id)])
        }
        let host = NSHostingView(rootView: Sidebar(browser: browser, coordinator: coordinator).frame(width: 280, height: 600))
        host.frame = CGRect(x: 0, y: 0, width: 280, height: 600)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.acceptsMouseMovedEvents = true
        window.level = .screenSaver
        window.makeKeyAndOrderFront(nil)
        let stage = Stage(coordinator: coordinator, window: window, host: host, tabs: tabs)
        try await stage.settle()
        return stage
    }

    @Test func clickingTheCloseControlClosesAnInactiveTabWithoutActivatingIt() async throws {
        let stage = try await makeStage()
        defer { stage.close() }
        let active = try #require(stage.browser.activeTab)
        let target = stage.tabs[3]
        #expect(target !== active)
        let point = try stage.control(of: target)
        try await stage.hover(point)
        stage.send(.leftMouseDown, at: point)
        stage.send(.leftMouseUp, at: point)
        try await stage.settle()
        #expect(stage.browser.tab(id: target.id) == nil)
        #expect(stage.browser.activeTab === active)
    }

    @Test func clickingTheUnpinControlUnpinsAPinnedTab() async throws {
        let stage = try await makeStage(pinning: 5)
        defer { stage.close() }
        let target = stage.tabs[5]
        #expect(target.pinnedURL != nil)
        let point = try stage.control(of: target)
        try await stage.hover(point)
        stage.send(.leftMouseDown, at: point)
        stage.send(.leftMouseUp, at: point)
        try await stage.settle()
        #expect(target.pinnedURL == nil)
        #expect(stage.browser.tab(id: target.id) != nil)
    }

    @Test func aPressThatSlidesOffTheCloseControlNeitherDragsNorCloses() async throws {
        let stage = try await makeStage()
        defer { stage.close() }
        let target = stage.tabs[3]
        let order = stage.browser.sidebarItems
        let point = try stage.control(of: target)
        try await stage.hover(point)
        stage.send(.leftMouseDown, at: point)
        var lifted = false
        for step in 1...10 {
            stage.send(.leftMouseDragged, at: CGPoint(x: point.x, y: point.y + CGFloat(step)))
            try await Task.sleep(for: .milliseconds(16))
            stage.window.layoutIfNeeded()
            stage.window.displayIfNeeded()
            lifted = lifted || stage.coordinator.sidebarDrag.drag != nil
        }
        stage.send(.leftMouseUp, at: CGPoint(x: point.x, y: point.y + 10))
        try await stage.settle()
        #expect(!lifted)
        #expect(stage.browser.tab(id: target.id) != nil)
        #expect(stage.browser.sidebarItems == order)
    }
}
