// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import os
import WebKit

extension AppCoordinator {
    func togglePin() {
        guard let tab = browser.activeTab else { return }
        if tab.isShowingPin {
            browser.unpin(tab)
        } else {
            browser.pin(tab)
        }
    }

    func printActivePage() {
        guard let tab = pageCommandTab else { return }
        PagePrinting.begin(for: tab.reader.presentedView ?? tab.webView)
    }

    func toggleFullScreen() {
        nativeWindow?.toggleFullScreen(nil)
    }

    func copyCurrentURL() {
        guard let tab = pageCommandTab else { return }
        copyLink(for: tab)
    }

    func copyLink(for tab: BrowserTab) {
        copyLinks(for: [tab])
    }

    func copyLinks(for tabs: [BrowserTab]) {
        let urls = tabs.compactMap { linkURL(for: $0) }
        guard !urls.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
        pasteboard.setString(urls.map(\.absoluteString).joined(separator: "\n"), forType: .string)
        let message: LocalizedStringResource = urls.count == 1 ? "Link Copied" : "Links Copied"
        notice.show(String(localized: message), symbol: "checkmark")
    }

    func linkURL(for tab: BrowserTab) -> URL? {
        guard !tab.urlString.isEmpty,
              let url = (tab.isMaterialised ? tab.webView.url : nil) ?? URL(string: tab.urlString),
              url.scheme != "about", !SystemPages.isStart(url)
        else { return nil }
        return url
    }

    func openTab(_ tab: BrowserTab) {
        browser.activate(tab)
    }

    func focusPane(_ tab: BrowserTab) {
        guard browser.activeTabID != tab.id, browser.isVisibleInSplit(tab) else { return }
        browser.activate(tab)
    }

    @discardableResult
    func openNewTab(url: URL? = nil) -> BrowserTab {
        let tab = browser.newTab(url: url)
        if url == nil {
            focusAddressBar()
        }
        return tab
    }

    func requestNewTab() {
        guard !palette.isOpen else {
            closePalette()
            return
        }
        browser.sidebarSelection.clear()
        openPalette()
        palette.markNewTab()
    }

    func focusAddressBar() {
        if settings.isMinimal {
            openPalette(seed: locationSeed)
            return
        }
        if !browserVisible {
            showBrowser()
        }
        requestAddressBarFocus()
    }

    var locationSeed: String? {
        browser.activeTab.flatMap { $0.isShowingStartPage ? nil : $0.urlString }
    }

    func openPalette(seed: String? = nil) {
        showBrowser()
        guard palette.open(seed: seed) else { return }
        linkPeek.suppress()
    }

    func togglePalette() {
        if palette.isOpen {
            closePalette()
        } else {
            openPalette()
        }
    }

    func closePalette() {
        palette.close()
        linkPeek.resume()
    }

    func confirmClearHistory() {
        let model = browser
        guard model.history.count > 0 else { return }
        Task {
            guard let choice = await ConfirmAlert.clear(.history()) else { return }
            await BrowsingData.clear(choice.kinds, range: choice.range, history: model.history, context: model.context)
        }
    }

    func organizeTabs() {
        guard TabOrganizer.isAvailable else {
            statusMessage = String(localized: "Organizing tabs needs a model: add a provider key or enable Apple Intelligence.")
            return
        }
        let model = browser
        let space = model.currentSpaceID
        let loose = model.currentSpaceTabs.filter {
            model.folder(containing: $0) == nil && $0.pinnedURL == nil
        }
        guard loose.count >= 4 else {
            statusMessage = String(localized: "Not enough loose tabs to organize.")
            return
        }
        statusMessage = String(localized: "Looking for related tabs…")
        let titles = loose.map { ($0.id, $0.title) }
        Task { [weak self, activity = model.modelActivity] in
            let outcome = await activity.perform { await TabOrganizer.propose(for: titles) }
            guard let self else { return }
            statusMessage = nil
            guard let outcome else { return }
            let plan: TabOrganizer.Plan
            switch outcome {
            case .plan(let proposed):
                plan = proposed
            case .empty:
                statusMessage = String(localized: "No related tabs to group.")
                return
            case .failed:
                statusMessage = String(localized: "The model couldn’t group the tabs. Try again.")
                return
            }
            let isStillShown = { [weak self] in self?.browser === model && model.currentSpaceID == space }
            guard isStillShown() else { return }
            let proposed = plan.folders.map { ($0.name, $0.tabIDs.count) }
            guard await ConfirmAlert.organize(folders: proposed), isStillShown() else { return }
            for folder in plan.folders {
                let members = folder.tabIDs
                    .compactMap { id in model.tabs.first { $0.id == id } }
                    .filter { $0.spaceID == space && model.folder(containing: $0) == nil && $0.pinnedURL == nil }
                guard members.count >= 2 else { continue }
                let made = model.createFolder(named: folder.name, containing: members)
                if model.tabs(in: made).count < 2 {
                    Pipeline.log.error("organized folder arrived empty; removing it")
                    model.deleteFolder(made)
                }
            }
        }
    }

    func closeAskingIfPinned(_ tab: BrowserTab, then closed: @escaping () -> Void = {}) {
        let model = browser
        guard tab.pinnedURL != nil else {
            model.close(tab)
            closed()
            return
        }
        Task {
            guard await ConfirmAlert.destructive(
                "Close this pinned tab?",
                detail: "Closing this tab also removes its pin. You can pin the page again later.",
                verb: "Close Tab"
            ) else { return }
            model.close(tab)
            closed()
        }
    }

    func closeActiveTabAskingIfPinned() {
        if closePeek() {
            return
        }
        guard let tab = browser.activeTab else { return }
        closeAskingIfPinned(tab)
    }

    func showHistory() {
        showBrowser()
        browser.showHistory()
    }

    func showDownloads() {
        showBrowser()
        browser.showDownloads()
    }

    func showReleaseNotes() {
        showBrowser()
        browser.showReleaseNotes()
    }

    func toggleSidePanel() {
        if !browserVisible {
            showBrowser()
        }
        sidePanel.toggleVisibility(seeding: showsLyrics ? .lyrics : .activity)
    }

    func toggleSidebar() {
        if !browserVisible {
            showBrowser()
        }
        sidebar.toggleVisible()
    }

    func toggleMinimal() {
        settings.isMinimal.toggle()
    }

    func moveMinimalBar() {
        settings.minimalBarEdge = settings.minimalBarEdge == .top ? .bottom : .top
    }

    func useProvider(_ provider: Provider) {
        guard provider.id != engine.selectedProvider.id else { return }
        modelSettings.providerID = provider.id
        reloadAssistantConfiguration()
    }

    func stopAgent() {
        endVoiceConversation()
        agentTurns.cancel()
        browser.modelActivity.cancelAll()
        speech.stopSpeaking()
    }

    func toggleMicListening() {
        if voiceInput.phase == .listening {
            Task { await voiceInput.finish() }
        } else if microphoneIsReady() {
            voiceInput.begin(endsOnSilence: true)
        }
    }
}
