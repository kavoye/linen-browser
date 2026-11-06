// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit

enum MenuItemImages {
    static let blank = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in true }
    nonisolated(unsafe) private static var observers: [NSObjectProtocol] = []

    static func show() {
        guard #available(macOS 27, *) else { return }
        observers = [NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { notification in
                guard Thread.isMainThread,
                      let index = notification.userInfo?["NSMenuItemIndex"] as? Int else { return }
                nonisolated(unsafe) let menu = notification.object as? NSMenu
                MainActor.assumeIsolated {
                    guard let menu, index < menu.numberOfItems,
                          let item = menu.item(at: index),
                          item.preferredImageVisibility != .visible else { return }
                    item.preferredImageVisibility = .visible
                }
            }
        }
    }
}
