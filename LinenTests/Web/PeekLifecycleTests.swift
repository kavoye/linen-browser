// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import Foundation
import Testing

@testable import Linen

@MainActor
@Suite(.boundedWebViews)
struct PeekLifecycleTests {
    private func coordinator() -> AppCoordinator {
        let context = BrowserProfileContext.shared(for: .privateBrowsing())
        return AppCoordinator(browser: BrowserModel(context: context, windowID: UUID()))
    }

    private func showPeek(in coordinator: AppCoordinator) -> BrowserTab {
        let tab = coordinator.browser.makePeekTab(URL(string: "about:blank")!)
        coordinator.peek.show(tab, from: coordinator.browser.activeTabID, at: .zero)
        return tab
    }

    @Test func ordinaryDismissalKeepsThePageAliveUntilTheAnimationEnds() async throws {
        let clock = TestClock()
        let coordinator = coordinator()
        let owner = coordinator.browser.newTab()
        let tab = showPeek(in: coordinator)
        defer { coordinator.closeWindow() }

        #expect(coordinator.peek.dismiss(using: coordinator.browser, clock: clock))
        #expect(coordinator.peek.tab == nil)
        #expect(!coordinator.peek.isQuiet)
        #expect(!tab.isClosed)
        try #require(await waitUntil { clock.pendingCount == 1 })
        clock.advance(by: .milliseconds(259))
        #expect(!tab.isClosed)
        clock.advance(by: .milliseconds(1))
        #expect(await waitUntil { tab.isClosed })
        #expect(!owner.isClosed)
    }

    @Test func immediateDismissalDetachesVisibleAndDepartingPeeks() {
        let coordinator = coordinator()
        let owner = coordinator.browser.newTab()
        let departing = showPeek(in: coordinator)
        #expect(coordinator.closePeek())
        let visible = showPeek(in: coordinator)
        defer { coordinator.closeWindow() }

        coordinator.closePeekImmediately()

        #expect(departing.isClosed)
        #expect(visible.isClosed)
        #expect(coordinator.peek.tab == nil)
        #expect(coordinator.peek.ownerID == nil)
        #expect(coordinator.peek.isQuiet)
        #expect(!owner.isClosed)
    }

    @Test func windowClosureDetachesVisibleAndDepartingPeeks() {
        let coordinator = coordinator()
        coordinator.browser.newTab()
        let departing = showPeek(in: coordinator)
        #expect(coordinator.closePeek())
        let visible = showPeek(in: coordinator)

        coordinator.closeWindow()

        #expect(departing.isClosed)
        #expect(visible.isClosed)
        #expect(coordinator.peek.tab == nil)
        #expect(coordinator.browser.tabs.isEmpty)
    }

    @Test func privateQuitDetachesVisibleAndDepartingPeeks() async {
        let app = BrowserApplication()
        let coordinator = coordinator()
        app.register(coordinator)
        coordinator.browser.newTab()
        let departing = showPeek(in: coordinator)
        #expect(coordinator.closePeek())
        let visible = showPeek(in: coordinator)
        defer { coordinator.closeWindow() }

        await app.clearDataOnQuitIfNeeded()

        #expect(departing.isClosed)
        #expect(visible.isClosed)
        #expect(coordinator.peek.tab == nil)
        #expect(coordinator.browser.tabs.isEmpty)
    }
}
