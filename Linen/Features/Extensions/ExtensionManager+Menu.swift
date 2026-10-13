// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import WebKit

extension ExtensionManager {
    func contextMenu(for id: String, in browser: BrowserModel? = nil) -> NSMenu? {
        guard let window = registeredWindow(in: browser), let context = contexts[id] else { return nil }
        let tab = window.browser?.activeTab.map { adapter(for: $0) }
        let menu = NSMenu()

        for item in context.action(for: tab)?.menuItems ?? [] {
            item.menu?.removeItem(item)
            menu.addItem(item)
        }
        if !menu.items.isEmpty {
            menu.addItem(.separator())
        }

        let known = record(for: id)
        let isPinned = known?.isPinned ?? true
        let pinTitle: LocalizedStringResource = isPinned ? "Hide from Toolbar" : "Show in Toolbar"
        menu.addItem(appMenuItem(
            title: String(localized: pinTitle),
            action: #selector(togglePinnedFromMenu(_:)),
            id: id, browser: browser
        ))
        if context.optionsPageURL != nil {
            menu.addItem(appMenuItem(
                title: String(localized: "extension.menu.settings", defaultValue: "Settings"),
                action: #selector(openOptionsFromMenu(_:)),
                id: id, browser: browser
            ))
        }
        menu.addItem(appMenuItem(
            title: String(localized: "Manage Extensions…"),
            action: #selector(manageFromMenu(_:)),
            id: id, browser: browser
        ))

        menu.addItem(.separator())
        if let page = window.browser?.activeTab, let url = URL(string: page.urlString),
           let website = Self.website(of: url),
           requestsAccess(id: id, to: url) || isBlocked(id: id, on: website) {
            let blocking = blockingHost(id: id, for: website)
            let host = blocking ?? website
            let item = appMenuItem(
                title: String(localized: "Allow on \(host)"),
                action: #selector(toggleWebsiteFromMenu(_:)),
                id: id, browser: browser
            )
            item.state = blocking == nil ? .on : .off
            (item.representedObject as? MenuTarget)?.host = host
            menu.addItem(item)
            menu.addItem(.separator())
        }
        menu.addItem(appMenuItem(
            title: String(localized: "Disable Extension"),
            action: #selector(disableFromMenu(_:)),
            id: id, browser: browser
        ))
        if known?.isSystem != true {
            menu.addItem(appMenuItem(
                title: String(localized: "Remove Extension…"),
                action: #selector(removeFromMenu(_:)),
                id: id, browser: browser
            ))
        }
        return menu
    }

    private final class MenuTarget {
        let id: String
        weak var browser: BrowserModel?
        var host: String?

        init(id: String, browser: BrowserModel?) {
            self.id = id
            self.browser = browser
        }
    }

    private func appMenuItem(title: String, action: Selector, id: String, browser: BrowserModel?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = MenuTarget(id: id, browser: browser ?? preferredWindowAdapter?.browser)
        return item
    }

    @objc private func togglePinnedFromMenu(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? MenuTarget,
              let record = record(for: target.id) else { return }
        setPinned(!record.isPinned, id: target.id)
    }

    @objc private func toggleWebsiteFromMenu(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? MenuTarget, let host = target.host else { return }
        setAllowed(isBlocked(id: target.id, on: host), on: host, id: target.id, reloading: target.browser)
    }

    @objc private func disableFromMenu(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? MenuTarget else { return }
        setEnabled(false, id: target.id)
    }

    @objc private func manageFromMenu(_ sender: NSMenuItem) {
        let target = sender.representedObject as? MenuTarget
        onManageExtensions?(target?.browser)
    }

    @objc private func openOptionsFromMenu(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? MenuTarget, let context = contexts[target.id] else { return }
        _ = openTab(context.optionsPageURL, in: target.browser)
    }

    @objc private func removeFromMenu(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? MenuTarget else { return }
        confirmUninstall(id: target.id)
    }

    func confirmUninstall(id: String) {
        let name = installed.first { $0.id == id }?.displayName ?? id
        let alert = NSAlert()
        alert.messageText = String(localized: "Remove “\(name)”?")
        alert.informativeText = String(localized: "The extension and its settings and data are removed from every profile.")
        if let icon = loadedIcon(for: id, size: 64) {
            alert.icon = icon
        }
        alert.addButton(withTitle: String(localized: "Remove Extension"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        uninstall(id: id)
    }
}
