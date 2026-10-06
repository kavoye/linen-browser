// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Testing

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct WindowMenuTests {
    @Test(arguments: [false, true])
    func nativeWindowTitlesLimitLongPageTitles(isPrivate: Bool) throws {
        let profile: Profile = isPrivate ? .privateBrowsing() : .original()
        let context = BrowserProfileContext.shared(for: profile)
        let coordinator = AppCoordinator(browser: BrowserModel(context: context, windowID: UUID()))
        defer { coordinator.closeWindow() }
        let tab = coordinator.browser.newTab()
        coordinator.showBrowser(activate: false)
        let window = try #require(coordinator.nativeWindow)
        let suffix = isPrivate ? String(localized: "Private Browsing") : coordinator.profiles.current.name
        let cases = [
            ("Short title", "Short title"),
            (String(repeating: "a", count: 40), String(repeating: "a", count: 40)),
            (String(repeating: "W", count: 300), String(repeating: "W", count: 39) + "…"),
            (String(repeating: "👨‍👩‍👧‍👦", count: 41), String(repeating: "👨‍👩‍👧‍👦", count: 39) + "…"),
        ]
        for (pageTitle, expectedTitle) in cases {
            tab.title = pageTitle
            coordinator.updateWindowAppearance()
            #expect(window.title == "\(expectedTitle) — \(suffix)")
            #expect(tab.title == pageTitle)
        }
    }

    @Test(arguments: [true, false])
    func bothWindowsStayRegisteredUntilClosed(installAfterFirstWindow: Bool) throws {
        let savedMainMenu = NSApp.mainMenu
        let savedWindowsMenu = NSApp.windowsMenu
        let savedHelpMenu = NSApp.helpMenu
        let savedServicesMenu = NSApp.servicesMenu
        NSApp.mainMenu = nil
        NSApp.windowsMenu = nil

        let app = BrowserApplication()
        let context = BrowserProfileContext.shared(for: .original())
        let first = AppCoordinator(browser: BrowserModel(context: context, windowID: UUID()))
        let second = AppCoordinator(browser: BrowserModel(context: context, windowID: UUID()))
        app.register(first)
        app.register(second)
        defer {
            first.closeWindow()
            second.closeWindow()
            NSApp.mainMenu = savedMainMenu
            NSApp.windowsMenu = savedWindowsMenu
            NSApp.helpMenu = savedHelpMenu
            NSApp.servicesMenu = savedServicesMenu
        }
        let menu = MainMenu(application: app)
        if !installAfterFirstWindow {
            menu.install()
        }
        first.showBrowser(activate: false)
        let firstWindow = try #require(first.nativeWindow)
        firstWindow.title = "First Browser Window"
        if installAfterFirstWindow {
            menu.install()
        }
        var windowsMenu = try #require(NSApp.windowsMenu)
        #expect(windowsMenu.items.filter { $0.title == firstWindow.title }.count == 1)

        second.showBrowser(activate: false)
        let secondWindow = try #require(second.nativeWindow)
        secondWindow.title = "Second Browser Window"
        #expect(windowsMenu.items.filter { $0.title == firstWindow.title }.count == 1)
        #expect(windowsMenu.items.filter { $0.title == secondWindow.title }.count == 1)

        menu.install()
        windowsMenu = try #require(NSApp.windowsMenu)
        #expect(windowsMenu.items.filter { $0.title == firstWindow.title }.count == 1)
        #expect(windowsMenu.items.filter { $0.title == secondWindow.title }.count == 1)
        let firstIndex = try #require(windowsMenu.items.firstIndex { $0.title == firstWindow.title })
        let firstItem = windowsMenu.items[firstIndex]
        #expect(firstItem.target as? NSWindow === firstWindow)
        #expect(firstItem.action == #selector(NSWindow.makeKeyAndOrderFront(_:)))
        #expect(firstItem.isEnabled)

        // Identical page/profile titles still represent distinct native windows.
        secondWindow.title = firstWindow.title
        let entries = windowsMenu.items.filter { $0.title == firstWindow.title }
        #expect(entries.count == 2)
        #expect(entries.contains { $0.target as? NSWindow === secondWindow })

        first.closeWindow()
        #expect(!windowsMenu.items.contains { $0.target as? NSWindow === firstWindow })
        #expect(windowsMenu.items.filter { $0.title == secondWindow.title }.count == 1)
    }
}
