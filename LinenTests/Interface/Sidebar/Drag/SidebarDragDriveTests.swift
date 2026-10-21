// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import Testing

@testable import Linen

@MainActor
@Suite(.serialized)
struct SidebarDragDriveTests {
    private func scrollViews(in view: NSView) -> [NSScrollView] {
        ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap { scrollViews(in: $0) }
    }

    private func post(_ type: NSEvent.EventType, at point: CGPoint, in window: NSWindow) {
        let flipped = CGPoint(x: point.x, y: window.contentView!.bounds.height - point.y)
        let event = NSEvent.mouseEvent(
            with: type, location: flipped, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )!
        if Self.queued {
            NSApp.postEvent(event, atStart: false)
        } else {
            window.sendEvent(event)
        }
    }

    nonisolated(unsafe) static var queued = false

    @Test(arguments: [false, true])
    func draggingATabDropsItBelowTheTarget(scrolled: Bool) async throws {
        let coordinator = AppCoordinator()
        let browser = coordinator.browser
        var tabs: [BrowserTab] = []
        for index in 0..<60 {
            let tab = browser.newTab(activate: index == 0)
            tab.urlString = "https://site\(index).example/"
            tab.title = "Site \(index)"
            tabs.append(tab)
        }
        let host = NSHostingView(rootView: Sidebar(browser: browser, coordinator: coordinator).frame(width: 280, height: 700))
        host.frame = CGRect(x: 0, y: 0, width: 280, height: 700)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        func settle() async throws {
            for _ in 0..<6 {
                try await Task.sleep(for: .milliseconds(20))
                window.layoutIfNeeded()
                window.displayIfNeeded()
            }
        }
        try await settle()
        if scrolled {
            let scroll = try #require(scrollViews(in: host).max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) })
            scroll.contentView.scroll(to: NSPoint(x: 0, y: 600))
            scroll.reflectScrolledClipView(scroll.contentView)
            try await settle()
        }
        let frames = coordinator.sidebarDrag.frames
        let origin = coordinator.sidebarDrag.listOriginInWindow
        let order = browser.sidebarItems
        let visible = order.compactMap { item -> (SidebarItem, CGRect)? in
            guard let frame = frames.windowFrame(of: item, listOrigin: origin), frame.minY > 80, frame.maxY < 600 else { return nil }
            return (item, frame)
        }
        try #require(visible.count >= 6)
        let (moving, from) = visible[0]
        let (target, to) = visible[4]
        let start = CGPoint(x: from.midX, y: from.midY)
        let end = CGPoint(x: to.midX, y: to.maxY - 3)
        post(.leftMouseDown, at: start, in: window)
        for step in 1...12 {
            let t = CGFloat(step) / 12
            post(.leftMouseDragged, at: CGPoint(x: start.x, y: start.y + (end.y - start.y) * t), in: window)
            try await Task.sleep(for: .milliseconds(16))
            window.layoutIfNeeded(); window.displayIfNeeded()
        }
        post(.leftMouseUp, at: end, in: window)
        try await settle()
        let after = browser.sidebarItems
        let movedIndex = after.firstIndex(of: moving)
        let targetIndex = after.firstIndex(of: target)
        #expect(movedIndex == (targetIndex ?? -2) + 1)
        window.orderOut(nil)
        for tab in tabs {
            browser.close(tab)
        }
    }

    @Test(arguments: [false, true])
    func draggingATabIntoThePinnedSectionEndsTheDrag(queued: Bool) async throws {
        Self.queued = queued
        defer { Self.queued = false }
        let coordinator = AppCoordinator()
        let browser = coordinator.browser
        var tabs: [BrowserTab] = []
        for index in 0..<20 {
            let tab = browser.newTab(activate: index == 0)
            tab.urlString = "https://site\(index).example/"
            tab.title = "Site \(index)"
            tabs.append(tab)
        }
        browser.setPinned(true, for: [.tab(tabs[19].id), .tab(tabs[18].id)])
        let host = NSHostingView(rootView: Sidebar(browser: browser, coordinator: coordinator).frame(width: 280, height: 700))
        host.frame = CGRect(x: 0, y: 0, width: 280, height: 700)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        func settle() async throws {
            for _ in 0..<6 {
                try await Task.sleep(for: .milliseconds(20))
                window.layoutIfNeeded()
                window.displayIfNeeded()
            }
        }
        try await settle()
        let frames = coordinator.sidebarDrag.frames
        let origin = coordinator.sidebarDrag.listOriginInWindow
        let order = browser.sidebarItems
        let kept = try #require(order.first { browser.isKept($0) })
        let loose = try #require(order.last { !browser.isKept($0) && frames[$0] != nil })
        let from = try #require(frames.windowFrame(of: loose, listOrigin: origin))
        let to = try #require(frames.windowFrame(of: kept, listOrigin: origin))
        let start = CGPoint(x: from.midX, y: from.midY)
        let end = CGPoint(x: to.midX, y: to.minY + 3)
        post(.leftMouseDown, at: start, in: window)
        for step in 1...16 {
            let t = CGFloat(step) / 16
            post(.leftMouseDragged, at: CGPoint(x: start.x, y: start.y + (end.y - start.y) * t), in: window)
            try await Task.sleep(for: .milliseconds(16))
            window.layoutIfNeeded()
            window.displayIfNeeded()
        }
        post(.leftMouseUp, at: end, in: window)
        try await settle()
        try await Task.sleep(for: .milliseconds(400))
        try await settle()

        #expect(browser.isKept(loose))
        #expect(coordinator.sidebarDrag.drag == nil)
        window.orderOut(nil)
        for tab in tabs {
            browser.close(tab)
        }
    }

    @Test func droppingATabOnThePinTargetEndsTheDrag() async throws {
        let coordinator = AppCoordinator()
        let browser = coordinator.browser
        var tabs: [BrowserTab] = []
        for index in 0..<20 {
            let tab = browser.newTab(activate: index == 0)
            tab.urlString = "https://site\(index).example/"
            tab.title = "Site \(index)"
            tabs.append(tab)
        }
        let host = NSHostingView(rootView: Sidebar(browser: browser, coordinator: coordinator).frame(width: 280, height: 700))
        host.frame = CGRect(x: 0, y: 0, width: 280, height: 700)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        func settle() async throws {
            for _ in 0..<6 {
                try await Task.sleep(for: .milliseconds(20))
                window.layoutIfNeeded()
                window.displayIfNeeded()
            }
        }
        try await settle()
        let frames = coordinator.sidebarDrag.frames
        let origin = coordinator.sidebarDrag.listOriginInWindow
        let order = browser.sidebarItems
        let first = try #require(frames.windowFrame(of: order[0], listOrigin: origin))
        let moving = order[5]
        let from = try #require(frames.windowFrame(of: moving, listOrigin: origin))
        let start = CGPoint(x: from.midX, y: from.midY)
        let end = CGPoint(x: from.midX, y: first.minY - 18)
        post(.leftMouseDown, at: start, in: window)
        for step in 1...20 {
            let t = CGFloat(step) / 20
            post(.leftMouseDragged, at: CGPoint(x: start.x, y: start.y + (end.y - start.y) * t), in: window)
            try await Task.sleep(for: .milliseconds(16))
            window.layoutIfNeeded()
            window.displayIfNeeded()
        }
        post(.leftMouseUp, at: end, in: window)
        try await settle()
        try await Task.sleep(for: .milliseconds(400))
        try await settle()
        #expect(browser.isKept(moving))
        #expect(coordinator.sidebarDrag.drag == nil)
        window.orderOut(nil)
        for tab in tabs {
            browser.close(tab)
        }
    }

    @Test(arguments: [false, true])
    func draggingATabOntoThePageSplitsIt(queued: Bool) async throws {
        Self.queued = queued
        defer { Self.queued = false }
        let coordinator = AppCoordinator()
        let browser = coordinator.browser
        var tabs: [BrowserTab] = []
        for index in 0..<8 {
            let tab = browser.newTab(activate: index == 0)
            tab.urlString = "https://site\(index).example/"
            tab.title = "Site \(index)"
            tabs.append(tab)
        }
        let sidebar = NSHostingView(rootView: Sidebar(browser: browser, coordinator: coordinator).frame(width: 280, height: 700))
        sidebar.frame = CGRect(x: 0, y: 0, width: 280, height: 700)
        let content = NSView(frame: CGRect(x: 0, y: 0, width: 880, height: 700))
        content.addSubview(sidebar)
        let window = NSWindow(contentRect: content.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        coordinator.sidebarDrag.contentFrameInWindow = CGRect(x: 280, y: 0, width: 600, height: 700)
        func settle() async throws {
            for _ in 0..<6 {
                try await Task.sleep(for: .milliseconds(20))
                window.layoutIfNeeded()
                window.displayIfNeeded()
            }
        }
        try await settle()
        let moving = tabs[5]
        let from = try #require(coordinator.sidebarDrag.frames.windowFrame(
            of: .tab(moving.id), listOrigin: coordinator.sidebarDrag.listOriginInWindow
        ))
        let start = CGPoint(x: from.midX, y: from.midY)
        let end = CGPoint(x: 860, y: 350)
        post(.leftMouseDown, at: start, in: window)
        for step in 1...20 {
            let t = CGFloat(step) / 20
            post(.leftMouseDragged, at: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t), in: window)
            try await Task.sleep(for: .milliseconds(16))
            window.layoutIfNeeded()
            window.displayIfNeeded()
        }
        #expect(coordinator.sidebarDrag.zone != .none, "zone \(coordinator.sidebarDrag.zone) carried \(String(describing: coordinator.sidebarDrag.carriedTabID))")
        post(.leftMouseUp, at: end, in: window)
        try await settle()
        try await Task.sleep(for: .milliseconds(400))
        try await settle()

        let split = try #require(browser.activeSplit)
        #expect(split.contains(moving.id))
        #expect(split.contains(tabs[0].id))
        #expect(coordinator.sidebarDrag.drag == nil)
        window.orderOut(nil)
        for tab in tabs {
            browser.close(tab)
        }
    }

    @Test(arguments: [false, true])
    func unpinningByDragLeavesTheSidebarDraggable(queued: Bool) async throws {
        Self.queued = queued
        defer { Self.queued = false }
        let coordinator = AppCoordinator()
        let browser = coordinator.browser
        var tabs: [BrowserTab] = []
        for index in 0..<20 {
            let tab = browser.newTab(activate: index == 0)
            tab.urlString = "https://site\(index).example/"
            tab.title = "Site \(index)"
            tabs.append(tab)
        }
        browser.setPinned(true, for: [.tab(tabs[19].id), .tab(tabs[18].id), .tab(tabs[17].id)])
        let host = NSHostingView(rootView: Sidebar(browser: browser, coordinator: coordinator).frame(width: 280, height: 700))
        host.frame = CGRect(x: 0, y: 0, width: 280, height: 700)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        func settle() async throws {
            for _ in 0..<6 {
                try await Task.sleep(for: .milliseconds(20))
                window.layoutIfNeeded()
                window.displayIfNeeded()
            }
        }
        func drag(through points: [CGPoint]) async throws {
            post(.leftMouseDown, at: points[0], in: window)
            for (from, to) in zip(points, points.dropFirst()) {
                for step in 1...10 {
                    let t = CGFloat(step) / 10
                    post(.leftMouseDragged, at: CGPoint(x: from.x, y: from.y + (to.y - from.y) * t), in: window)
                    try await Task.sleep(for: .milliseconds(16))
                    window.layoutIfNeeded()
                    window.displayIfNeeded()
                }
            }
            post(.leftMouseUp, at: points[points.count - 1], in: window)
            try await settle()
            try await Task.sleep(for: .milliseconds(400))
            try await settle()
        }
        try await settle()
        let frames = coordinator.sidebarDrag.frames
        func spot(_ item: SidebarItem, _ edge: CGFloat = 0.5) throws -> CGPoint {
            let frame = try #require(frames.windowFrame(of: item, listOrigin: coordinator.sidebarDrag.listOriginInWindow))
            return CGPoint(x: frame.midX, y: frame.minY + frame.height * edge)
        }
        let order = browser.sidebarItems
        let pinned = try #require(order.first { browser.isKept($0) })
        let firstLoose = try #require(order.first { !browser.isKept($0) })
        let farLoose = order.filter { !browser.isKept($0) }[3]
        try await drag(through: [try spot(pinned), try spot(farLoose), try spot(firstLoose, 0.1), try spot(farLoose, 0.9)])
        #expect(!browser.isKept(pinned))
        #expect(coordinator.sidebarDrag.drag == nil)

        let next = browser.sidebarItems.filter { !browser.isKept($0) }[5]
        let target = try #require(browser.sidebarItems.first { browser.isKept($0) })
        try await drag(through: [try spot(next), try spot(target, 0.1)])
        #expect(browser.isKept(next))
        #expect(coordinator.sidebarDrag.drag == nil)
        window.orderOut(nil)
        for tab in tabs {
            browser.close(tab)
        }
    }
}
