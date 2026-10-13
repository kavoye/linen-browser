// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Testing

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct TabsHoldMenuTests {
    private func titles(_ menu: NSMenu) -> [String] {
        menu.items.map { $0.isSeparatorItem ? "-" : $0.title }
    }

    private func perform(_ title: String, in menu: NSMenu) throws {
        let index = try #require(menu.items.firstIndex { $0.title == title }, "\(title) is in the menu")
        menu.performActionForItem(at: index)
    }

    @Test func withoutATabTheMenuOnlyOpensThings() {
        let coordinator = AppCoordinator()
        defer { coordinator.closeWindow() }

        let menu = TabsHoldMenu.menu(browser: coordinator.browser, coordinator: coordinator)

        #expect(titles(menu) == ["New Tab", "New Folder", "Search Everything…"])
    }

    @Test func oneTabCanBeDuplicatedPinnedOrClosedButHasNoOthers() {
        let coordinator = AppCoordinator()
        defer { coordinator.closeWindow() }
        coordinator.browser.newTab()

        let menu = TabsHoldMenu.menu(browser: coordinator.browser, coordinator: coordinator)

        #expect(titles(menu) == [
            "New Tab", "New Folder", "Search Everything…",
            "-", "Duplicate Tab", "Pin Tab",
            "-", "Close Tab",
        ])
    }

    @Test func aSecondTabAndAClosedTabAddTheirCommands() throws {
        let coordinator = AppCoordinator()
        defer { coordinator.closeWindow() }
        let browser = coordinator.browser
        browser.newTab()
        browser.newTab()
        browser.newTab()
        coordinator.closeActiveTabAskingIfPinned()
        #expect(browser.canReopenClosedTab)

        let menu = TabsHoldMenu.menu(browser: browser, coordinator: coordinator)

        #expect(titles(menu).contains("Reopen Last Closed Tab"))
        #expect(titles(menu).last == "Close Other Tabs")
    }

    @Test func duplicateTabAddsATab() throws {
        let coordinator = AppCoordinator()
        defer { coordinator.closeWindow() }
        coordinator.browser.newTab()

        try perform("Duplicate Tab", in: TabsHoldMenu.menu(browser: coordinator.browser, coordinator: coordinator))

        #expect(coordinator.browser.tabs.count == 2)
    }

    @Test func newFolderAddsAFolderAndShowsTheTabList() throws {
        let coordinator = AppCoordinator()
        defer { coordinator.closeWindow() }
        let folders = coordinator.browser.folders.count

        try perform("New Folder", in: TabsHoldMenu.menu(browser: coordinator.browser, coordinator: coordinator))

        #expect(coordinator.browser.folders.count == folders + 1)
        #expect(coordinator.overlays.isTabListOpen)
    }
}
