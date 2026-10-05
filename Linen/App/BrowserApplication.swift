// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Observation
import WebKit

/// Owns native windows. Browsing data belongs to a profile; selection and
/// running assistant tasks belong to the coordinator that opened them.
@MainActor
@Observable
final class BrowserApplication {
    static let shared = BrowserApplication()

    private(set) var windows: [AppCoordinator] = []
    private(set) var activeWindowID: UUID?
    private(set) var isTerminating = false
    private var privateSessionCleanups: [UUID: Task<Void, Never>] = [:]
    let updates = UpdateController()
    private var isReady = false
    private var queuedURLs: [URL] = []
    private var usedProfiles: [UUID: BrowserProfileContext] = [:]
    private var focusOrder: [UUID] = []
    private let defaults = BrowserMCPServer.appDefaults
    private static let lastWindowKey = "browser.lastFocusedWindow"
    private var mainMenu: MainMenu?
    private let mediaMessages = WindowMediaMessages()

    var activeCoordinator: AppCoordinator? {
        windows.first { $0.isKeyWindow }
            ?? windows.first { $0.windowID == activeWindowID }
            ?? windows.last
    }

    var externalLinkTarget: AppCoordinator? {
        if let activeCoordinator, !activeCoordinator.profiles.isPrivate {
            return activeCoordinator
        }
        return focusOrder.reversed().compactMap { id in
            windows.first { $0.windowID == id && !$0.profiles.isPrivate }
        }.first ?? windows.last { !$0.profiles.isPrivate }
    }

    @ObservationIgnored lazy var mcpServer = BrowserMCPServer(
        defaults: BrowserMCPServer.appDefaults,
        target: { [weak self] in
            guard let coordinator = self?.activeCoordinator,
                  !coordinator.profiles.isPrivate, !coordinator.isSwitchingProfile
            else { return nil }
            return coordinator.browser
        },
        available: { [weak self] browser in
            self?.windows.contains {
                $0.browser === browser && !$0.profiles.isPrivate
                    && !$0.isSwitchingProfile && !$0.agentTurns.isRunning
            } == true
        }
    )

    func bootstrap() async {
        guard !isReady else { return }
        OutputDucker.restoreAfterUncleanExit()
        installSharedRouting()
        // AppKit needs the Window menu before windows are shown to list them in the Dock.
        let menu = MainMenu(application: self)
        mainMenu = menu
        menu.install()
        let lastWindowID = defaults.string(forKey: Self.lastWindowKey).flatMap(UUID.init(uuidString:))
        let catalog = ProfileStore.shared
        for profile in catalog.profiles {
            let context = BrowserProfileContext.shared(for: profile)
            for saved in BrowserModel.savedWindows(in: context.database).reversed() {
                var id = saved.id
                if id == BrowserModel.legacyWindowID || windows.contains(where: { $0.windowID == id }) {
                    let uniqueID = UUID()
                    if BrowserModel.remapSavedWindow(in: context.database, from: id, to: uniqueID) {
                        id = uniqueID
                    }
                }
                newWindow(profile: profile, windowID: id, restoring: true)
            }
        }
        if windows.isEmpty {
            newWindow(profile: catalog.current)
        }
        if let profileID = catalog.launchProfileID,
           let profile = catalog.profiles.first(where: { $0.id == profileID }) {
            let window = windows.last { $0.profiles.current.id == profileID }
                ?? newWindow(profile: profile, show: false)
            window.showBrowser()
        } else if let lastWindowID, let window = windows.first(where: { $0.windowID == lastWindowID }) {
            window.showBrowser()
        }
        isReady = true
        let queued = queuedURLs
        queuedURLs.removeAll()
        openFromAnotherApp(queued)
        mcpServer.resume()
    }

    @discardableResult
    func newWindow(
        profile: Profile? = nil,
        settingsOwner: Profile? = nil,
        windowID: UUID = UUID(),
        restoring: Bool = false,
        show: Bool = true,
        urls: [URL] = []
    ) -> AppCoordinator {
        let profile = profile ?? activeCoordinator?.profiles.current ?? ProfileStore.shared.current
        let context = BrowserProfileContext.shared(for: profile, settingsOwner: settingsOwner)
        let browser = BrowserModel(context: context, windowID: windowID)
        let selection = ProfileStore.selection(profile: profile)
        if profile.isPrivate, let settingsOwner, !settingsOwner.isPrivate {
            selection.markCurrent(settingsOwner)
            selection.markCurrent(profile)
        }
        let coordinator = AppCoordinator(browser: browser, profiles: selection)
        register(coordinator)
        coordinator.prepareBrowser(restoring: restoring, show: show, urls: urls)
        if show {
            focus(coordinator)
        }
        return coordinator
    }

    func register(_ coordinator: AppCoordinator) {
        guard !windows.contains(where: { $0 === coordinator }) else { return }
        coordinator.application = self
        windows.append(coordinator)
        remember(coordinator.browser.context)
        configureExtensions(coordinator.extensions, profile: coordinator.profiles.current)
    }

    @discardableResult
    func ensureActiveWindow() -> AppCoordinator {
        activeCoordinator ?? newWindow(profile: ProfileStore.shared.current)
    }

    func showBrowser() {
        ensureActiveWindow().showBrowser()
    }

    func focus(_ coordinator: AppCoordinator) {
        guard windows.contains(where: { $0 === coordinator }) else { return }
        activeWindowID = coordinator.windowID
        focusOrder.removeAll { $0 == coordinator.windowID }
        focusOrder.append(coordinator.windowID)
        if !coordinator.profiles.isPrivate, !AppDatabase.isRunningTests {
            defaults.set(coordinator.windowID.uuidString, forKey: Self.lastWindowKey)
        }
        coordinator.extensions.focus(browser: coordinator.browser)
        for window in windows {
            window.activation.setSuspended(window !== coordinator)
        }
    }

    func didClose(_ coordinator: AppCoordinator) {
        guard !isTerminating else { return }
        mcpServer.disconnect(browser: coordinator.browser)
        coordinator.extensions.unregister(browser: coordinator.browser)
        windows.removeAll { $0 === coordinator }
        focusOrder.removeAll { $0 == coordinator.windowID }
        if activeWindowID == coordinator.windowID {
            activeWindowID = windows.last?.windowID
        }
    }

    func openFromAnotherApp(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard isReady else {
            queuedURLs.append(contentsOf: urls)
            return
        }
        let target = externalLinkTarget ?? newWindow(profile: ProfileStore.shared.current)
        target.openFromAnotherApp(urls)
    }

    var canReopenWindow: Bool {
        mostRecentlyClosedWindow() != nil
    }

    func reopenLastClosedWindow() {
        guard let (profile, saved) = mostRecentlyClosedWindow() else { return }
        var id = saved.id
        if windows.contains(where: { $0.windowID == id }) {
            let uniqueID = UUID()
            guard BrowserModel.remapSavedWindow(
                in: BrowserProfileContext.shared(for: profile).database, from: id, to: uniqueID
            ) else { return }
            id = uniqueID
        }
        newWindow(profile: profile, windowID: id, restoring: true)
    }

    private func mostRecentlyClosedWindow() -> (Profile, BrowserModel.SavedBrowserWindow)? {
        ProfileStore.shared.profiles.flatMap { profile in
            BrowserModel.savedWindows(in: BrowserProfileContext.shared(for: profile).database, includeClosed: true)
                .filter { $0.closedAt != nil }
                .map { (profile, $0) }
        }.max { ($0.1.closedAt ?? .distantPast) < ($1.1.closedAt ?? .distantPast) }
    }

    func coordinator(for webView: WKWebView) -> AppCoordinator? {
        windows.first { coordinator in
            coordinator.browser.tabs.contains { $0.isMaterialised && $0.webView === webView }
                || coordinator.peek.tab.map { $0.isMaterialised && $0.webView === webView } == true
        }
    }

    private func installSharedRouting() {
        mediaMessages.application = self
        GeolocationBridge.shared.tabResolver = { [weak self] webView in
            self?.coordinator(for: webView)?.browser.tabs.first { $0.isMaterialised && $0.webView === webView }
        }
        NotificationBridge.shared.tabResolver = GeolocationBridge.shared.tabResolver
        TabWebView.refreshHoverShield = { [weak self] in
            self?.windows.forEach { $0.applyHoverShield() }
        }
        PageClickWatcher.shared.onWebViewClick = { [weak self] webView, point in
            self?.coordinator(for: webView)?.downloadFlights.noteClick(at: point)
        }
        AutofillSuggestions.shared.openSettings = { [weak self] in
            self?.ensureActiveWindow().openSettings(.autofill)
        }
    }

    func prepareWebScripts(for coordinator: AppCoordinator) {
        remember(coordinator.browser.context)
        let pool = coordinator.browser.context.webViewPool
        pool.prepare(
            scriptSource: MediaCenter.frameScriptSource,
            handlerName: MediaCenter.frameScriptHandlerName,
            handler: mediaMessages
        )
    }

    func prepareToTerminate() {
        isTerminating = true
        mcpServer.stop()
        for coordinator in windows {
            coordinator.stopAgent()
            coordinator.voiceInput.cancel()
            coordinator.browser.saveBlocking()
            coordinator.conversationLog.saveBlocking()
        }
    }

    func endPrivateSession(_ context: BrowserProfileContext) {
        guard context.profile.isPrivate else { return }
        let cleanupID = UUID()
        privateSessionCleanups[cleanupID] = Task { [weak self] in
            await context.endPrivateSession()
            self?.privateSessionCleanups[cleanupID] = nil
        }
    }

    func clearDataOnQuitIfNeeded() async {
        for coordinator in windows where coordinator.profiles.isPrivate {
            coordinator.closePeekImmediately()
            coordinator.browser.closeAllTabs(saving: false)
            coordinator.conversationLog.clearAll()
            endPrivateSession(coordinator.browser.context)
        }
        for cleanup in Array(privateSessionCleanups.values) {
            await cleanup.value
        }
        for context in usedProfiles.values where context.settings.clearsDataOnQuit {
            let tabs = windows.filter { $0.browser.context === context }.flatMap { $0.browser.tabs }
            await BrowsingData.clearEverything(
                history: context.history, agent: context.conversationLog,
                tabs: tabs, context: context
            )
        }
    }

    var hasDataToClearOnQuit: Bool {
        !privateSessionCleanups.isEmpty || windows.contains { $0.profiles.isPrivate }
            || usedProfiles.values.contains { $0.settings.clearsDataOnQuit }
    }

    func finishTermination() {
        for context in usedProfiles.values {
            context.downloads.clearOnQuitIfNeeded(context.settings.downloadRetention)
        }
    }

    private func remember(_ context: BrowserProfileContext) {
        if !context.profile.isPrivate {
            usedProfiles[context.profile.id] = context
        }
    }

    func forgetProfile(_ id: UUID) {
        usedProfiles[id] = nil
    }

    func configureExtensions(_ manager: ExtensionManager, profile: Profile) {
        manager.onOpenWindow = { [weak self, weak manager] configuration in
            guard let self, manager != nil else { return nil }
            let targetProfile = configuration.shouldBePrivate
                ? Profile.privateBrowsing()
                : (profile.isPrivate ? ProfileStore.shared.current : profile)
            let coordinator = self.newWindow(
                profile: targetProfile, settingsOwner: profile,
                show: configuration.shouldBeFocused
            )
            let initialTabs = coordinator.browser.tabs
            // New tabs appear first in the sidebar, so insert in reverse to keep the requested order.
            for url in configuration.tabURLs.reversed() {
                coordinator.openNewTab(url: url)
            }
            for adapter in configuration.tabs.compactMap({ $0 as? ExtensionTabAdapter }) {
                guard let source = adapter.browser, let tab = adapter.tab else { continue }
                _ = coordinator.browser.adoptTab(tab, from: source)
            }
            if !configuration.tabURLs.isEmpty || !configuration.tabs.isEmpty {
                for tab in initialTabs {
                    coordinator.browser.close(tab)
                }
            }
            return coordinator.extensions.adapter(for: coordinator.browser)
        }
    }
}

private final class WindowMediaMessages: NSObject, WKScriptMessageHandler {
    weak var application: BrowserApplication?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let webView = message.webView else { return }
        application?.coordinator(for: webView)?.media.receiveScriptMessage(
            message.body as? String ?? "", from: webView, isMainFrame: message.frameInfo.isMainFrame
        )
    }
}
