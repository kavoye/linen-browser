// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit

enum PeekExit {
    static let resizeReach: CGFloat = 12

    static func hasLeft(pointer: CGPoint?, frame: CGRect, trailingReach: CGFloat = 0) -> Bool {
        guard !frame.isEmpty else { return false }
        guard let pointer else { return true }
        var reach = frame
        reach.size.width += trailingReach
        return !reach.contains(pointer)
    }
}

@MainActor
final class PeekWatch {
    private let center: NotificationCenter
    private var monitors: [Any] = []
    private var observers: [any NSObjectProtocol] = []

    init(center: NotificationCenter = .default) {
        self.center = center
    }

    func start(window: NSWindow?, check: @escaping @MainActor () -> Void) {
        stop()
        if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { event in
            check()
            return event
        }) {
            monitors.append(local)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { _ in
            check()
        }) {
            monitors.append(global)
        }
        observe(NSApplication.didResignActiveNotification, object: nil, check: check)
        if let window {
            observe(NSWindow.didResignKeyNotification, object: window, check: check)
        }
    }

    private func observe(_ name: Notification.Name, object: AnyObject?, check: @escaping @MainActor () -> Void) {
        observers.append(center.addObserver(forName: name, object: object, queue: .main) { _ in
            MainActor.assumeIsolated { check() }
        })
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        observers.forEach(center.removeObserver)
        observers = []
    }
}
