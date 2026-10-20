// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import OSLog
import SwiftUI
import WebKit

struct DeveloperBadge: View {
    let tab: BrowserTab
    let coordinator: AppCoordinator

    @State private var anchor = MenuAnchorBox()

    var body: some View {
        ChromeIcon(symbol: "ladybug", size: 10, weight: .semibold, help: String(localized: "Developer Tools")) {
            let menu = DeveloperMenu.make(for: tab, coordinator: coordinator)
            guard let view = anchor.view else {
                menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
                return
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: view)
        }
        .background { MenuAnchor(box: anchor) }
    }
}

extension BrowserTab {
    func setDeveloperMode(_ isOn: Bool) {
        withAnimation(Theme.Motion.drift) {
            context.settings.setDeveloperMode(isOn, for: URL(string: urlString))
        }
        updateDeveloperTools { tools in
            if !isOn {
                tools = DeveloperTools()
            }
        }
    }
}

extension AppCoordinator {
    func copyScreenshot(of tab: BrowserTab) {
        Task { @MainActor in
            do {
                let image = try await tab.webView.takeSnapshot(configuration: WKSnapshotConfiguration())
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
                Self.flash(over: tab.webView)
                notice.show(String(localized: "Screenshot Copied"), symbol: "camera.viewfinder")
            } catch {
                DeveloperMenu.log.notice("Screenshot failed: \(error.localizedDescription, privacy: .public)")
                notice.show(String(localized: "Couldn’t take a screenshot"), symbol: "camera.viewfinder", isWarning: true)
            }
        }
    }

    private static func flash(over webView: WKWebView) {
        guard let container = webView.superview else { return }
        let flash = NSView(frame: webView.frame)
        flash.wantsLayer = true
        flash.layer?.backgroundColor = NSColor.black.cgColor
        flash.alphaValue = 0.45
        container.addSubview(flash, positioned: .above, relativeTo: webView)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            flash.animator().alphaValue = 0
        }
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            flash.removeFromSuperview()
        }
    }
}

@MainActor
enum DeveloperMenu {
    static let log = Logger(subsystem: "com.kavoye.Linen", category: "developer")

    static func make(for tab: BrowserTab, coordinator: AppCoordinator) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(
            title: String(localized: "Show Web Inspector"),
            image: symbol("wrench.and.screwdriver"),
            key: "i",
            modifiers: [.command, .option]
        ) { [weak tab] in
            tab?.showWebInspector()
        }
        menu.addItem(title: String(localized: "Copy Screenshot"), image: symbol("camera.viewfinder")) { [weak tab, weak coordinator] in
            guard let tab, let coordinator else { return }
            coordinator.copyScreenshot(of: tab)
        }

        menu.addItem(.separator())
        menu.addItem(title: String(localized: "Show Frame Rate"), image: symbol("gauge.with.needle")) { [weak tab] in
            tab?.updateDeveloperTools { $0.showsFrameRate.toggle() }
        }.state = tab.developerTools.showsFrameRate ? .on : .off
        menu.addItem(title: String(localized: "Outline Elements"), image: symbol("square.dashed")) { [weak tab] in
            tab?.updateDeveloperTools { $0.outlinesElements.toggle() }
        }.state = tab.developerTools.outlinesElements ? .on : .off
        menu.addItem(submenu(appearanceMenu(for: tab), title: String(localized: "Page Appearance"), image: symbol("circle.lefthalf.filled")))

        let browsers = otherBrowsers()
        if !browsers.isEmpty, let url = URL(string: tab.urlString) {
            menu.addItem(.separator())
            menu.addItem(submenu(openInMenu(url, browsers: browsers), title: String(localized: "Open In"), image: symbol("arrow.up.forward.app")))
        }

        menu.addItem(.separator())
        menu.addItem(title: String(localized: "Restart Page"), image: symbol("arrow.trianglehead.2.clockwise")) { [weak tab] in
            tab?.restartPage()
        }
        menu.addItem(title: String(localized: "Clear Website Data…"), image: symbol("trash")) { [weak tab] in
            guard let tab else { return }
            confirmClearingData(for: tab)
        }
        if let host = DeveloperMode.host(of: URL(string: tab.urlString)) {
            menu.addItem(.separator())
            menu.addItem(title: String(localized: "Turn Off Developer Mode for “\(host)”")) { [weak tab] in
                tab?.setDeveloperMode(false)
            }
        }
        return menu
    }

    private static func appearanceMenu(for tab: BrowserTab) -> NSMenu {
        let menu = NSMenu()
        for appearance in DeveloperTools.Appearance.allCases {
            if appearance == .light {
                menu.addItem(.separator())
            }
            menu.addItem(title: String(localized: appearance.title)) { [weak tab] in
                tab?.updateDeveloperTools { $0.appearance = appearance }
            }.state = tab.developerTools.appearance == appearance ? .on : .off
        }
        return menu
    }

    private static func openInMenu(_ url: URL, browsers: [URL]) -> NSMenu {
        let menu = NSMenu()
        for browser in browsers {
            let icon = NSWorkspace.shared.icon(forFile: browser.path(percentEncoded: false))
            icon.size = NSSize(width: 16, height: 16)
            menu.addItem(title: FileManager.default.displayName(atPath: browser.path(percentEncoded: false)), image: icon) {
                NSWorkspace.shared.open([url], withApplicationAt: browser, configuration: NSWorkspace.OpenConfiguration())
            }
        }
        return menu
    }

    private static func otherBrowsers() -> [URL] {
        guard let probe = URL(string: "https://example.com") else { return [] }
        var seen: Set<String> = [Bundle.main.bundleIdentifier ?? ""]
        return NSWorkspace.shared.urlsForApplications(toOpen: probe)
            .filter { seen.insert(Bundle(url: $0)?.bundleIdentifier ?? $0.path()).inserted }
            .sorted {
                FileManager.default.displayName(atPath: $0.path(percentEncoded: false))
                    .localizedStandardCompare(FileManager.default.displayName(atPath: $1.path(percentEncoded: false)))
                    == .orderedAscending
            }
    }

    private static func submenu(_ menu: NSMenu, title: String, image: NSImage?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = image
        item.submenu = menu
        return item
    }

    private static func confirmClearingData(for tab: BrowserTab) {
        guard let host = DeveloperMode.host(of: URL(string: tab.urlString)) else { return }
        Task { @MainActor [weak tab] in
            guard await ConfirmAlert.destructive(
                "Clear website data for “\(host)”?",
                detail: "Cookies, caches and storage for this website are removed, and the page reloads.",
                verb: "Clear"
            ), let tab else { return }
            await WebsiteData.remove([host], from: tab.context.dataStore)
            tab.webView.reloadFromOrigin()
        }
    }

    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }
}
