// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct SpaceCoordinatorTests {
    private struct Fixture {
        let app = BrowserApplication()
        let coordinator: AppCoordinator
        let spaces: SpaceStore
        let work: Profile
        let files: [URL]

        init() {
            let profileFile = TestFiles.directory.appendingPathComponent("space-profiles-\(UUID()).json")
            let spaceFile = TestFiles.directory.appendingPathComponent("spaces-\(UUID()).json")
            files = [profileFile, spaceFile]
            let catalog = ProfileStore(file: profileFile)
            work = catalog.add(name: "Work")
            spaces = SpaceStore(file: spaceFile)
            let selection = ProfileStore.selection(profile: .original(), catalog: catalog)
            let browser = BrowserModel(context: .shared(for: .original()), windowID: UUID())
            coordinator = AppCoordinator(browser: browser, profiles: selection, spaceStore: spaces)
            app.register(coordinator)
            coordinator.prepareBrowser(restoring: false, show: false)
            coordinator.refreshSpaces()
        }

        var workSpace: Space? {
            spaces.spaces(for: work.id).first
        }

        func addSharedSpace() -> Space {
            let space = spaces.add(name: "Recipes", symbol: "fork.knife", color: .orange, profileID: Profile.originalID)
            coordinator.refreshSpaces()
            return space
        }

        func close() {
            coordinator.closeParkedTabModels()
            for window in app.windows {
                window.closeWindow()
                UserDefaults.standard.removeObject(
                    forKey: "NSWindow Frame linen.browser.window.\(window.windowID.uuidString)"
                )
            }
            BrowserProfileContext.forget(work.id)
            files.forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }

    @Test func lookingUpAPeerNeverBuildsItsModel() throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let coordinator = fixture.coordinator
        let workSpace = try #require(fixture.workSpace)

        #expect(coordinator.peerModel(for: workSpace.id) == nil)
        #expect(coordinator.loomColor(forSpace: workSpace.id) == nil)
        #expect(coordinator.parkedModels[fixture.work.id] == nil)

        coordinator.preparePeerModel(for: workSpace.id)

        let parked = try #require(coordinator.parkedModels[fixture.work.id])
        #expect(coordinator.peerModel(for: workSpace.id) === parked)
    }

    @Test func activatingATabInAnotherSpaceFollowsIt() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let coordinator = fixture.coordinator
        let browser = coordinator.browser
        let home = try #require(coordinator.currentSpace)
        let homeTab = browser.newTab(url: URL(string: "https://home.example/"))
        let recipes = fixture.addSharedSpace()
        coordinator.switchSpace(to: recipes)
        await coordinator.spaceSlider.untilAtRest()
        try #require(browser.currentSpaceID == recipes.id)

        browser.activate(homeTab)

        #expect(browser.currentSpaceID == home.id)
        #expect(browser.activeTab === homeTab)
        #expect(coordinator.spaceSlider.isAtRest)
        browser.cancelPendingSave()
    }

    @Test func activatingATabInAnotherSpaceWhileLandingLeavesTheSlideAtRest() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let coordinator = fixture.coordinator
        let original = coordinator.browser
        let home = try #require(coordinator.currentSpace)
        let workSpace = try #require(fixture.workSpace)
        let recipes = fixture.addSharedSpace()
        coordinator.switchSpace(to: recipes)
        await coordinator.spaceSlider.untilAtRest()
        let recipeTab = try #require(original.activeTab)
        coordinator.switchSpace(to: home)
        await coordinator.spaceSlider.untilAtRest()
        try #require(original.currentSpaceID == home.id)

        coordinator.switchSpace(to: workSpace)
        try #require(coordinator.spaceSlider.isLanding)
        original.activate(recipeTab)

        #expect(original.currentSpaceID == home.id)
        await coordinator.spaceSlider.untilAtRest()

        #expect(coordinator.spaceSlider.isAtRest)
        #expect(!coordinator.overlays.spaceSlide.isSliding)
        #expect(coordinator.profiles.current.id == fixture.work.id)
        #expect(coordinator.browser.currentSpaceID == workSpace.id)

        coordinator.switchSpace(to: home)
        await coordinator.spaceSlider.untilAtRest()

        #expect(coordinator.browser === original)
        #expect(original.currentSpaceID == home.id)
        #expect(original.activeTab?.spaceID == home.id)
        original.cancelPendingSave()
    }

    @Test func deletingASharedSpaceClosesOnlyItsTabs() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let coordinator = fixture.coordinator
        let browser = coordinator.browser
        let home = try #require(coordinator.currentSpace)
        let kept = browser.newTab(url: URL(string: "https://kept.example/"))
        let recipes = fixture.addSharedSpace()
        coordinator.switchSpace(to: recipes)
        await coordinator.spaceSlider.untilAtRest()
        let doomed = try #require(browser.activeTab)

        await coordinator.deleteSpace(recipes)

        #expect(fixture.spaces.space(id: recipes.id) == nil)
        #expect(browser.tabs.contains { $0 === kept })
        #expect(!browser.tabs.contains { $0 === doomed })
        #expect(browser.currentSpaceID == home.id)
        #expect(coordinator.profiles.profiles.contains { $0.id == Profile.originalID })
        browser.cancelPendingSave()
    }

    @Test func deletingTheLastSpaceOfTheCurrentProfileRemovesTheProfile() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let coordinator = fixture.coordinator
        let workSpace = try #require(fixture.workSpace)
        await coordinator.switchProfile(to: fixture.work, landingIn: workSpace.id)
        try #require(coordinator.profiles.current.id == fixture.work.id)

        await coordinator.deleteSpace(workSpace)

        #expect(!coordinator.profiles.profiles.contains { $0.id == fixture.work.id })
        #expect(fixture.spaces.spaces(for: fixture.work.id).isEmpty)
        #expect(coordinator.profiles.current.id == Profile.originalID)
        #expect(coordinator.browser.currentSpaceID.flatMap(fixture.spaces.space(id:))?.profileID == Profile.originalID)
        coordinator.browser.cancelPendingSave()
    }

    @Test func aDeleteConfirmedForOneSpaceKeepsTheProfile() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let workSpace = try #require(fixture.workSpace)

        await fixture.coordinator.removeSpace(workSpace, confirmedAsLast: false)

        #expect(fixture.spaces.space(id: workSpace.id) != nil)
        #expect(fixture.coordinator.profiles.profiles.contains { $0.id == fixture.work.id })
    }

    @Test func renamingTheOnlySpaceOfAProfileRenamesTheProfile() throws {
        let fixture = Fixture()
        defer { fixture.close() }
        var workSpace = try #require(fixture.workSpace)

        workSpace.name = "Clients"
        fixture.coordinator.updateSpace(workSpace)

        #expect(fixture.coordinator.profiles.profiles.first { $0.id == fixture.work.id }?.name == "Clients")
    }

    @Test func removingTheCurrentSpaceLeavesItWithoutWaiting() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let coordinator = fixture.coordinator
        let recipes = fixture.addSharedSpace()
        let adjacent = try #require(fixture.spaces.adjacent(to: recipes.id))
        coordinator.switchSpace(to: recipes)
        await coordinator.spaceSlider.untilAtRest()
        let clock = ContinuousClock()

        let elapsed = await clock.measure {
            await coordinator.removeSpace(recipes, confirmedAsLast: false)
        }

        #expect(fixture.spaces.space(id: recipes.id) == nil)
        #expect(adjacent.id == fixture.workSpace?.id)
        #expect(coordinator.browser.currentSpaceID == adjacent.id)
        #expect(coordinator.profiles.current.id == fixture.work.id)
        #expect(coordinator.spaceSlider.isAtRest)
        #expect(elapsed < .seconds(1))
        coordinator.browser.cancelPendingSave()
    }
}
