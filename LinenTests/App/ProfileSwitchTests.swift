// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

/// Switching profiles is the one move that takes the whole window apart and
/// puts it back: the tabs go, the stores are swapped, the session comes back
/// from another database. What must hold is that nothing of the old profile
/// survives into the new one.
@MainActor
@Suite(.serialized, .boundedWebViews)
struct ProfileSwitchTests {
    private struct Fixture {
        let app = BrowserApplication()
        let coordinator: AppCoordinator
        let work: Profile
        let file: URL

        init() {
            file = TestFiles.directory.appendingPathComponent("profile-switch-\(UUID()).json")
            let catalog = ProfileStore(file: file)
            work = catalog.add(name: "Work")
            let selection = ProfileStore.selection(profile: .original(), catalog: catalog)
            let browser = BrowserModel(context: .shared(for: .original()), windowID: UUID())
            coordinator = AppCoordinator(browser: browser, profiles: selection)
            app.register(coordinator)
            coordinator.prepareBrowser(restoring: false, show: false)
        }

        func close() {
            app.windows.forEach { $0.closeWindow() }
            BrowserProfileContext.forget(work.id)
            try? FileManager.default.removeItem(at: file)
        }
    }

    @Test func switchingToTheProfileYouAreInChangesNothing() async {
        let fixture = Fixture()
        defer { fixture.close() }
        let coordinator = fixture.coordinator
        let current = coordinator.profiles.current
        let tab = coordinator.browser.newTab(url: URL(string: "https://example.com/"))

        await coordinator.switchProfile(to: current)

        #expect(coordinator.profiles.current.id == current.id)
        #expect(coordinator.browser.tabs.contains { $0 === tab }, "the session was left alone")
        #expect(!coordinator.isSwitchingProfile)
    }

    @Test func aSwitchClearsItsOwnStateWhenItIsDone() async {
        let fixture = Fixture()
        defer { fixture.close() }
        let coordinator = fixture.coordinator

        await coordinator.switchProfile(to: fixture.work)

        #expect(coordinator.switchingTo == nil, "the switching state does not outlive the switch")
        #expect(!coordinator.isSwitchingProfile)
        coordinator.browser.cancelPendingSave()
    }

    @Test func theTabsOfTheProfileYouLeaveDoNotComeWithYou() async {
        let fixture = Fixture()
        defer { fixture.close() }
        let coordinator = fixture.coordinator
        let left = coordinator.browser.newTab(url: URL(string: "https://leaving.example/"))

        await coordinator.switchProfile(to: fixture.work)

        #expect(!coordinator.browser.tabs.contains { $0 === left })
        #expect(coordinator.profiles.current.id == fixture.work.id)
        coordinator.browser.cancelPendingSave()
    }

    @Test func closingPrivateBrowsingLeavesTheRegularWindowOpen() {
        let fixture = Fixture()
        defer { fixture.close() }
        let regular = fixture.coordinator
        let regularTab = regular.browser.newTab()
        let context = BrowserProfileContext.shared(for: .privateBrowsing())
        let privateBrowser = BrowserModel(context: context, windowID: UUID())
        let privateWindow = AppCoordinator(browser: privateBrowser)
        let privateTab = privateBrowser.newTab()

        #expect(privateWindow.profiles.isPrivate)
        #expect(privateTab.isPrivate)
        #expect(!context.dataStore.isPersistent)
        privateWindow.closeWindow()

        #expect(privateBrowser.tabs.isEmpty)
        #expect(privateTab.isClosed)
        #expect(!regular.profiles.isPrivate)
        #expect(regular.browser.tabs.contains { $0 === regularTab })
        #expect(!regularTab.isClosed)
        regular.browser.cancelPendingSave()
    }

    @Test func aSwitchSaysWhichProfileItLandedIn() async {
        let fixture = Fixture()
        defer { fixture.close() }
        let coordinator = fixture.coordinator

        await coordinator.switchProfile(to: fixture.work)

        #expect(coordinator.notice == fixture.work.name)
        coordinator.browser.cancelPendingSave()
    }

    @Test func switchingBackReplacesTheExtensionWindowRegistration() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let coordinator = fixture.coordinator
        let browser = coordinator.browser
        let personalManager = coordinator.extensions
        let originalWindow = try #require(personalManager.adapter(for: browser))
        let personalTab = try #require(browser.activeTab)
        let personalTabID = personalTab.id
        let url = try #require(URL(string: "about:blank"))
        let departingPeek = browser.makePeekTab(url)
        coordinator.peek.show(departingPeek, from: personalTabID, at: .zero)
        #expect(coordinator.closePeek())
        let visiblePeek = browser.makePeekTab(url)
        coordinator.peek.show(visiblePeek, from: personalTabID, at: .zero)

        await coordinator.switchProfile(to: fixture.work)

        let workManager = coordinator.extensions
        let workWindow = try #require(workManager.adapter(for: browser))
        #expect(personalManager !== workManager)
        #expect(personalManager.adapter(for: browser) == nil)
        #expect(originalWindow.browser == nil)
        #expect(personalTab.isClosed)
        #expect(departingPeek.isClosed && visiblePeek.isClosed)
        #expect(coordinator.peek.tab == nil)
        #expect(visiblePeek.onOpenInNewTab == nil)

        await coordinator.switchProfile(to: .original())

        #expect(coordinator.extensions === personalManager)
        #expect(personalManager.adapter(for: browser) !== originalWindow)
        #expect(workManager.adapter(for: browser) == nil)
        #expect(workWindow.browser == nil)
        #expect(browser.activeTab?.id == personalTabID)
        #expect(!coordinator.isSwitchingProfile)
    }
}
