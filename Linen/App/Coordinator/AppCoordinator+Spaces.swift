// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os
import SwiftUI

extension AppCoordinator {
    // MARK: - Spaces

    var currentSpace: Space? {
        spaceStore.space(id: browser.currentSpaceID)
    }

    var showsSpaces: Bool {
        !profiles.isPrivate && browser.currentSpaceID != nil
    }

    func adoptSpaces(for profile: Profile) {
        guard !profile.isPrivate else {
            browser.adoptSpaces([])
            return
        }
        spaceStore.reconcile(with: profiles.profiles)
        adoptOwnSpaces(in: browser)
        for model in parkedModels.values {
            adoptOwnSpaces(in: model)
        }
        spaceSlider.mountPeers()
        if let target = overlays.spaceEditor, case .edit(let id) = target, spaceStore.space(id: id) == nil {
            spaceSlider.closeEditor()
        }
    }

    func adoptOwnSpaces(in model: BrowserModel) {
        model.adoptSpaces(spaceStore.spaces(for: model.context.profile.id).map(\.id))
    }

    func refreshSpaces() {
        guard !profiles.isPrivate else { return }
        adoptSpaces(for: profiles.current)
    }

    func switchSpace(to space: Space) {
        guard !profiles.isPrivate else { return }
        spaceSlider.switchSpace(to: space)
    }

    func foreignProfile(of space: Space) -> Profile? {
        guard space.profileID != profiles.current.id else { return nil }
        return profiles.profiles.first { $0.id == space.profileID }
    }

    func peerModel(for spaceID: UUID) -> BrowserModel? {
        guard let space = spaceStore.space(id: spaceID) else { return nil }
        guard let profile = foreignProfile(of: space) else { return browser }
        return parkedModels[profile.id]
    }

    func preparePeerModel(for spaceID: UUID) {
        guard let space = spaceStore.space(id: spaceID), let profile = foreignProfile(of: space) else { return }
        _ = tabModel(for: profile)
    }

    func loomColor(forSpace id: UUID) -> NSColor? {
        guard let model = peerModel(for: id) else { return nil }
        guard let tab = model.lastActiveTab(inSpace: id), tab.internalPage == nil,
              !ChromeBand.showsStartPage(for: tab) else { return nil }
        return tab.pageColor
    }

    func confirmDeleteSpace(_ space: Space) async {
        guard spaceStore.canRemove(space) else { return }
        let isLast = spaceStore.ownsLastSpace(of: space)
        let detail: LocalizedStringResource = isLast
            ? "Its tabs close, and its sign-ins, history and other data are deleted. You can’t undo this."
            : "Its tabs close. You can’t undo this."
        guard await ConfirmAlert.destructive("Delete “\(space.name)”?", detail: detail, verb: "Delete") else { return }
        await removeSpace(space, confirmedAsLast: isLast)
    }

    func removeSpace(_ space: Space, confirmedAsLast isLast: Bool) async {
        spaceSlider.closeEditor()
        await spaceSlider.untilAtRest()
        if browser.currentSpaceID == space.id, showsSpaces, !settings.isMinimal,
           let target = spaceStore.adjacent(to: space.id) {
            switchSpace(to: target)
            await spaceSlider.untilAtRest()
        }
        guard spaceStore.ownsLastSpace(of: space) == isLast else {
            Pipeline.log.notice("spaces: kept a space whose deletion would now remove its profile")
            return
        }
        await deleteSpace(space)
    }

    func moveToSpace(_ items: [SidebarItem], space: Space) {
        guard space.profileID == profiles.current.id else { return }
        browser.move(items, toSpace: space.id)
    }

    @discardableResult
    func createSpace(
        name: String,
        symbol: String,
        color: TabFolderColor,
        sharingWith shared: Space?
    ) -> Space {
        let profileID = shared?.profileID ?? profiles.add(name: name, symbol: symbol, color: color).id
        let space = spaceStore.add(name: name, symbol: symbol, color: color, profileID: profileID)
        refreshSpacesEverywhere()
        spaceSlider.enterCreated(space)
        return space
    }

    var allWindows: [AppCoordinator] {
        application?.windows ?? [self]
    }

    private func refreshSpacesEverywhere() {
        for window in allWindows {
            window.refreshSpaces()
        }
    }

    func updateSpace(_ space: Space) {
        spaceStore.update(space)
        guard let stored = spaceStore.space(id: space.id), spaceStore.ownsLastSpace(of: stored),
              stored.profileID != Profile.originalID,
              let profile = profiles.profiles.first(where: { $0.id == stored.profileID }) else { return }
        profiles.rename(profile, to: stored.name)
        profiles.setAppearance(of: profile, symbol: stored.symbol, color: stored.color)
    }

    func deleteSpace(_ space: Space) async {
        guard spaceStore.canRemove(space),
              let profile = profiles.profiles.first(where: { $0.id == space.profileID }) else { return }
        for window in allWindows {
            await window.spaceSlider.untilAtRest()
        }
        if let sibling = spaceStore.spaces(for: space.profileID).first(where: { $0.id != space.id }) {
            closeSpace(space, in: profile, fallingBackTo: sibling)
        } else {
            await removeProfile(profile, of: space)
        }
        refreshSpacesEverywhere()
    }

    private func closeSpace(_ space: Space, in profile: Profile, fallingBackTo sibling: Space) {
        for window in allWindows {
            if window.browser.currentSpaceID == space.id {
                window.spaceSlider.jump(to: sibling)
            }
            if window.profiles.current.id == space.profileID {
                window.browser.closeSpace(space.id)
            }
            window.parkedModels[space.profileID]?.closeSpace(space.id)
        }
        spaceStore.remove(space)
        BrowserModel.forgetSpace(space.id, in: BrowserProfileContext.shared(for: profile).database)
    }

    private func removeProfile(_ profile: Profile, of space: Space) async {
        guard let fallback = spaceStore.adjacent(to: space.id),
              let other = profiles.profiles.first(where: { $0.id == fallback.profileID }) else { return }
        for window in allWindows where window.profiles.current.id == profile.id {
            await window.switchProfile(to: other, landingIn: fallback.id)
            guard window.isClosed || window.profiles.current.id != profile.id else {
                Pipeline.log.error("spaces: a window stayed on a profile being removed")
                return
            }
        }
        await application?.prepareToRemove(profile: profile)
        spaceStore.remove(space)
        await profiles.remove(profile)
    }
}
