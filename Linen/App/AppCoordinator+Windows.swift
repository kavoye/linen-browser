// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import WebKit

extension AppCoordinator {
    func tabDidClose(_ tab: BrowserTab) {
        if conversationSpaceID == tab.id {
            endVoiceConversation()
        }
        playedPages[tab.id] = nil
        FaviconTint.forget(tab.id)
        if peek.belongs(to: tab.id) {
            closePeek()
        }
        if media.controlledTabID == tab.id {
            media.releaseControl()
            dockSuccessor(to: tab.id)
        }
        if agentTurns.closeTab(tab.id) {
            voiceInput.clearTranscript()
            statusMessage = nil
        }
    }

    func configureWindowCallbacks() {
        let extensionTabClosed = browser.onTabClosed
        browser.onTabClosed = { [weak self] tab in
            extensionTabClosed?(tab)
            self?.tabDidClose(tab)
        }
        let extensionTabChanged = browser.onActiveTabChanged
        browser.onActiveTabChanged = { [weak self] newTab, previousTab in
            extensionTabChanged?(newTab, previousTab)
            guard let self else { return }
            if conversationSpaceID != browser.activeSpaceID {
                conversationVoice?.stop()
            }
            followMedia(to: newTab, from: previousTab)
            applyHoverShield()
            updateWindowAppearance()
        }
    }

    var windowTitle: String {
        let pageTitle = browser.activeTab?.title ?? String(localized: "New Window")
        // AppKit also uses this title in the Dock menu, where it sets the menu's width.
        let title = pageTitle.count > 40 ? String(pageTitle.prefix(39)) + "…" : pageTitle
        return profiles.isPrivate
            ? String(localized: "\(title) — Private Browsing")
            : String(localized: "\(title) — \(profiles.current.name)")
    }

    var otherWindows: [AppCoordinator] {
        application?.windows.filter { $0 !== self && $0.browser.context === browser.context } ?? []
    }

    func requestNewWindow(isPrivate: Bool = false) {
        guard !isClosed else { return }
        let app = application ?? BrowserApplication.shared
        app.newWindow(
            profile: isPrivate ? .privateBrowsing()
                : (profiles.isPrivate ? profiles.profileToReturnTo : profiles.current),
            settingsOwner: profiles.isPrivate ? profiles.profileToReturnTo : profiles.current
        )
    }

    @discardableResult
    func openLinkInNewWindow(_ url: URL, isPrivate: Bool = false) -> AppCoordinator? {
        guard !isClosed else { return nil }
        let app = application ?? BrowserApplication.shared
        let settingsOwner = profiles.isPrivate ? profiles.profileToReturnTo : profiles.current
        return app.newWindow(
            profile: (isPrivate || profiles.isPrivate) ? .privateBrowsing() : profiles.current,
            settingsOwner: settingsOwner, urls: [url]
        )
    }

    func closeWindow() {
        if let nativeWindow {
            nativeWindow.performClose(nil)
        } else {
            windowDidClose()
        }
    }

    func windowDidBecomeKey() {
        application?.focus(self)
        activation.setSuspended(false)
        updateWindowAppearance()
    }

    func windowDidResignKey() {
        extensions.focus(browser: nil)
        activation.setSuspended(true)
        controlDownAt = nil
        browser.endTabSwitching()
        tabPreview.dismiss()
    }

    func updateWindowAppearance() {
        if profiles.isPrivate {
            browser.context.favicons.schemeOverride = .dark
        } else {
            switch settings.appearance {
            case .system:
                browser.context.favicons.schemeOverride = nil
            case .light:
                browser.context.favicons.schemeOverride = .light
            case .dark:
                browser.context.favicons.schemeOverride = .dark
            }
        }
        nativeWindow?.appearance = profiles.isPrivate
            ? NSAppearance(named: .darkAqua) : settings.appearance.nsAppearance
        nativeWindow?.title = windowTitle
        updateHandoff()
        reloadFaviconsIfSchemeChanged()
    }

    var handoffURL: URL? {
        guard !profiles.isPrivate, let tab = browser.activeTab, !tab.isPrivate,
              let url = tab.committedURL ?? URL(string: tab.urlString),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }

    func updateHandoff() {
        guard let nativeWindow else { return }
        guard let url = handoffURL else {
            nativeWindow.userActivity?.invalidate()
            nativeWindow.userActivity = nil
            return
        }
        let activity = nativeWindow.userActivity
            ?? NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        activity.webpageURL = url
        activity.title = browser.activeTab?.title
        nativeWindow.userActivity = activity
    }

    func windowDidClose() {
        guard application?.isTerminating != true, beginClosingWindow() else { return }
        if !profiles.isPrivate {
            browser.markSessionClosed()
        }
        conversationLog.saveBlocking()
        stopAgent()
        voiceInput.cancel()
        voicePreparation?.cancel()
        voicePreparation = nil
        activation.stop()
        memoryPressure.stop()
        media.releaseControl()
        media.stopWatching()
        downloadFlights.stopWatching()
        linkPeek.end()
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
        if let tabSwitchMonitor {
            NSEvent.removeMonitor(tabSwitchMonitor)
        }
        escapeMonitor = nil
        tabSwitchMonitor = nil
        if let resignActiveObserver {
            NotificationCenter.default.removeObserver(resignActiveObserver)
        }
        resignActiveObserver = nil
        browser.cancelPendingSave()
        closePeekImmediately()
        browser.closeAllTabs(saving: false)
        application?.didClose(self)
        nativeWindow?.userActivity?.invalidate()
        releaseWindowHost()
        if profiles.isPrivate {
            browser.downloads.forgetPrivateDownloads()
            conversationLog.clearAll()
            privateSession = nil
            let context = browser.context
            if let application {
                application.endPrivateSession(context)
            } else {
                Task { await context.endPrivateSession() }
            }
        }
    }

    @discardableResult
    func moveTab(_ tab: BrowserTab, to destination: AppCoordinator) -> Bool {
        guard !isClosed, !destination.isClosed,
              destination.browser.adoptTab(tab, from: browser) else { return false }
        destination.showBrowser()
        return true
    }

    func moveTabToNewWindow(_ tab: BrowserTab) {
        // Private windows have independent cookie stores. Moving a live page
        // between those stores would also move its authenticated session.
        guard !profiles.isPrivate, let application else { return }
        let destination = application.newWindow(profile: profiles.current)
        let placeholder = destination.browser.activeTab
        if moveTab(tab, to: destination), let placeholder {
            destination.browser.close(placeholder, recordForReopening: false)
        }
    }

    @discardableResult
    func finishWindowDrag(_ items: [SidebarItem], at screenPoint: NSPoint) -> Bool {
        guard let sourceWindow = nativeWindow, !sourceWindow.frame.contains(screenPoint),
              !profiles.isPrivate, let application
        else { return false }
        let ids = browser.sidebarTree.expanded(Set(items)).compactMap { item -> UUID? in
            guard case .tab(let id) = item else { return nil }
            return id
        }
        let tabs = browser.tabs.filter { ids.contains($0.id) }
        guard !tabs.isEmpty else { return false }
        let target = NSApp.orderedWindows.lazy
            .filter { $0.isVisible && !$0.isMiniaturized && $0.frame.contains(screenPoint) }
            .compactMap { window in application.windows.first { $0.nativeWindow === window } }
            .first { $0 !== self }
        if let target, target.browser.context !== browser.context {
            return false
        }
        let destination = target ?? application.newWindow(profile: profiles.current)
        let placeholder = target == nil ? destination.browser.activeTab : nil
        for tab in tabs {
            _ = destination.browser.adoptTab(tab, from: browser)
        }
        if let placeholder {
            destination.browser.close(placeholder, recordForReopening: false)
        }
        if target == nil, let window = destination.nativeWindow {
            window.setFrameTopLeftPoint(NSPoint(x: screenPoint.x - 100, y: screenPoint.y + 20))
        }
        destination.showBrowser()
        return true
    }
}
