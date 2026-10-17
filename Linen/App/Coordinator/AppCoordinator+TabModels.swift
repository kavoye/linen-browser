// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os
import WebKit

@MainActor
final class ActiveTabModel: AgentTurnBrowsing {
    var model: BrowserModel

    init(_ model: BrowserModel) {
        self.model = model
    }

    func ensureAgentTabID() -> UUID {
        model.ensureAgentTabID()
    }

    func agentAnchorID(forTab tabID: UUID) -> UUID {
        model.agentAnchorID(forTab: tabID)
    }

    func agentContextSummary(mentionedTabIDs: [UUID]) -> String? {
        model.agentContextSummary(mentionedTabIDs: mentionedTabIDs)
    }

    func setAgentWorking(_ isWorking: Bool, inAnchor anchorID: UUID) {
        model.setAgentWorking(isWorking, inAnchor: anchorID)
    }
}

extension AppCoordinator {
    // MARK: - Tab models

    func bindTabModel(_ model: BrowserModel) {
        model.onTabWillTransferOut = { [weak self] tab in
            self?.agentWillLose(tab)
        }
        model.onPageColorWillChange = { [weak self] tab in
            self?.spaceSlider.pageColorWillChange(on: tab)
        }
        model.onActiveTabLeftSpace = { [weak self, weak model] tab in
            guard let self, let model else { return }
            spaceSlider.follow(tab, in: model)
        }
        model.onAnchorChanged = { [weak self] from, to in
            if self?.voiceConversation.anchorID == from {
                self?.voiceConversation.session?.stop()
            }
            self?.agentTurns.reassignAnchor(from: from, to: to)
        }
        model.onLinkHovered = { [weak self] tab, url, modifiers, anchor in
            guard let self else { return }
            noteLinkModifiers(modifiers)
            linkPeek.hovered(url, flags: modifiers, tabID: tab.id, anchor: anchor)
        }
        model.onOpenInPeek = { [weak self] tab, url, origin in
            self?.openPeek(url: url, from: tab, at: origin)
        }
        model.onOpenInNewWindow = { [weak self] _, url, isPrivate, activate in
            self?.openLinkInNewWindow(url, isPrivate: isPrivate, activate: activate)
        }
        model.onSummarizeLink = { [weak self] tab, url, anchor in
            guard let self, let tab else { return }
            linkPeek.show(url, tabID: tab.id, anchor: anchor)
        }
        model.onContentProcessTerminated = { [weak self] tab in
            guard let self else { return }
            tab.hasVideo = false
            media.pageDidReset(tab.webView)
        }
        model.onPictureInPictureChanged = { [weak self] tab, isOut in
            Pipeline.log.notice("media: WebKit reports the picture \(isOut ? "out" : "home", privacy: .public)")
            self?.media.setPictureInPicture(isOut, for: tab.webView, source: .webKit)
        }
        model.onPictureReturnExpected = { [weak self] tab in
            guard let self, media.notePictureReturnAsk(for: tab.webView) else { return }
            Pipeline.log.notice("media: the floating window wants to hand the video back")
            makeRoomForPicture(in: tab.webView)
        }
    }

    func tabModel(for profile: Profile) -> BrowserModel {
        if browser.context.profile.id == profile.id {
            return browser
        }
        if let parked = parkedModels[profile.id] {
            return parked
        }
        let model = BrowserModel(context: .shared(for: profile), windowID: browser.windowID)
        bindTabModel(model)
        followClosedTabs(in: model)
        adoptOwnSpaces(in: model)
        model.restoreSession(lazily: true)
        parkedModels[profile.id] = model
        return model
    }

    func park(_ model: BrowserModel) {
        for tab in model.tabs where tab.isMaterialised {
            tab.webView.pauseAllMediaPlayback(completionHandler: nil)
        }
        followClosedTabs(in: model)
        parkedModels[model.context.profile.id] = model
    }

    private func followClosedTabs(in model: BrowserModel) {
        model.onTabClosed = { [weak self, weak model] tab in
            guard let model else { return }
            self?.tabDidClose(tab, in: model)
        }
        followReopening(in: model)
    }

    func followReopening(in model: BrowserModel) {
        model.onTabReopened = { [weak self] tabID, tab in
            self?.agentTurns.reopenTab(tabID, as: tab.id)
        }
        model.onClosedTabForgotten = { [weak self] tabID in
            self?.agentTurns.forgetClosedTab(tabID)
        }
    }

    func saveParkedTabModels() {
        for model in parkedModels.values {
            model.saveBlocking()
        }
    }

    func forgetTabModel(for profileID: UUID) {
        guard let model = parkedModels.removeValue(forKey: profileID) else { return }
        model.cancelPendingSave()
        model.closeAllTabs(saving: false)
    }

    func closeParkedTabModels() {
        saveParkedTabModels()
        for profileID in Array(parkedModels.keys) {
            forgetTabModel(for: profileID)
        }
    }

    func relieveMemoryPressure(_ level: MemoryPressureMonitor.Level) {
        browser.relieveMemoryPressure(level)
        for model in parkedModels.values {
            model.relieveMemoryPressure(level)
        }
    }

    func sleepIdleTabs() {
        browser.sleepIdleTabs()
        for model in parkedModels.values {
            model.sleepIdleTabs()
        }
    }
}
