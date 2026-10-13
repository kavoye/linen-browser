// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import WebKit

extension AppCoordinator {
    func tabDidClose(_ tab: BrowserTab) {
        if voiceConversation.spaceID == tab.id {
            endVoiceConversation()
        }
        mediaDock.forget(tab.id)
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
            if voiceConversation.spaceID != browser.activeSpaceID {
                voiceConversation.session?.stop()
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
        let appearance = profiles.isPrivate
            ? NSAppearance(named: .darkAqua) : settings.appearance.nsAppearance
        if let nativeWindow, nativeWindow.appearance?.name != appearance?.name {
            crossfadeAppearanceChange(in: nativeWindow, to: appearance)
        }
        nativeWindow?.title = windowTitle
        updateHandoff()
        reloadFaviconsIfSchemeChanged()
    }

    private func crossfadeAppearanceChange(in window: NSWindow, to appearance: NSAppearance?) {
        let before = window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
        let after = (appearance ?? NSApp.effectiveAppearance).bestMatch(from: [.aqua, .darkAqua])
        if window.isVisible, before != after,
           let layer = window.contentView?.superview?.layer ?? window.contentView?.layer {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.3
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(fade, forKey: "appearance")
        }
        window.appearance = appearance
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
        voiceRoute.cancelPreparation()
        activation.stop()
        memoryPressure.stop()
        archiveSweeper.stop()
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
        if let voicePreferencesObserver {
            NotificationCenter.default.removeObserver(voicePreferencesObserver)
        }
        voicePreferencesObserver = nil
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
}
