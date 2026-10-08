// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import os
import WebKit

extension AppCoordinator {
    // MARK: - Launch

    func bootstrap() async {
        prepareBrowser(restoring: true)
    }

    func prepareBrowser(restoring: Bool, show: Bool = true, urls: [URL] = []) {
        guard !isBootstrapped else { return }
        isBootstrapped = true
        var timing = BootstrapTiming()
        Pipeline.log.notice("bootstrap: begin")
        OutputDucker.restoreAfterUncleanExit()
        applyProfileStores(profiles.current)
        followSettings()
        timing.mark("profile and assistant")
        memoryPressure.onPressure = { [weak self] level in
            self?.browser.relieveMemoryPressure(level)
        }
        memoryPressure.start()
        if application == nil {
            let menu = MainMenu(coordinator: self)
            menu.install()
            mainMenu = menu
        }
        prepareWindowWebServices()
        timing.mark("web setup")
        if restoring {
            browser.restoreSession()
        }
        for url in urls.reversed() {
            browser.newTab(url: url, transition: .link)
        }
        browser.ensureActiveTab()
        retainAgentMemory()
        archiveSweeper.onSweep = { [weak self] in
            self?.browser.archiveStaleTabs()
        }
        archiveSweeper.start()
        timing.mark("session")
        wireMedia()
        browser.onSpaceAnchorChanged = { [weak self] from, to in
            if self?.conversationSpaceID == from {
                self?.conversationVoice?.stop()
            }
            self?.agentTurns.reassignSpace(from: from, to: to)
        }
        browser.onLinkHovered = { [weak self] tab, url, modifiers, anchor in
            guard let self else { return }
            noteLinkModifiers(modifiers)
            linkPeek.hovered(url, flags: modifiers, tabID: tab.id, anchor: anchor)
        }
        browser.onOpenInPeek = { [weak self] tab, url, origin in
            self?.openPeek(url: url, from: tab, at: origin)
        }
        browser.onOpenInNewWindow = { [weak self] _, url, isPrivate in
            self?.openLinkInNewWindow(url, isPrivate: isPrivate)
        }
        browser.onSummarizeLink = { [weak self] tab, url, anchor in
            guard let self, let tab else { return }
            linkPeek.show(url, tabID: tab.id, anchor: anchor)
        }
        linkPeek.begin()
        if application == nil || application?.windows.count == 1 {
            onboarding.beginIfNeeded()
        }
        if onboarding.isPresented {
            prepareWindowBloom()
        }
        timing.mark("window preparation")
        showBrowser(activate: show)
        timing.mark("show window")
        if application == nil {
            mcpServer.resume()
        }
        if onboarding.isPresented {
            bloomWindowOpen()
        }
        if !AppDatabase.ownsSession {
            self.show(notice: String(localized: "Another copy of Linen is running. Changes in this window won’t be saved."))
        }
        drainQueuedExternalURLs()
        timing.mark("post-window setup")

        if application == nil || application?.windows.count == 1 {
            startUpdates()
        }
        MoveToApplications.reregisterDefaultBrowserIfNeeded()
        timing.mark("updates")
        Task { [weak self] in
            guard let self, application == nil || application?.windows.count == 1,
                  await releaseNotes.shouldOpenForNewVersion() else { return }
            guard !isClosed else { return }
            showReleaseNotes()
        }

        Task { [extensions] in
            await extensions.start()
            await extensions.updateInstalledIfDue()
        }

        activation.onPress = { [weak self] in
            guard let self, isKeyWindow, !onboarding.isPresented, microphoneIsReady() else { return }
            voiceInput.begin()
        }
        activation.onRelease = { [weak self] in
            guard let self, !onboarding.isPresented else { return }
            voiceInput.scheduleFinish()
        }
        activation.setSuspended(!isKeyWindow)
        activation.start()
        installKeyMonitors()

        timing.mark("services")
        timing.log()
    }

    func prepareWindowWebServices() {
        browser.context.contentBlocker.refresh()
        if let application {
            application.prepareWebScripts(for: self)
        } else {
            browser.context.webViewPool.prepare(
                scriptSource: MediaCenter.frameScriptSource,
                handlerName: MediaCenter.frameScriptHandlerName,
                handler: media.frameScriptHandler
            )
        }
        browser.context.webViewPool.addScript(
            GeolocationBridge.scriptSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            handlerName: GeolocationBridge.handlerName,
            handler: GeolocationBridge.shared
        )
        browser.context.webViewPool.addScript(
            NotificationBridge.scriptSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            handlerName: NotificationBridge.handlerName,
            handler: NotificationBridge.shared
        )
        if application == nil {
            GeolocationBridge.shared.tabResolver = { [weak self] webView in
                self?.browser.tabs.first { $0.isMaterialised && $0.webView === webView }
            }
            NotificationBridge.shared.tabResolver = GeolocationBridge.shared.tabResolver
        }
        browser.context.webViewPool.installExtensionController(extensions.controller)
    }

    func engine(for configuration: Provider) -> any ModelProvider {
        modelProviders.resolve(configuration)
    }

    func configureEngines() {
        LLMSettings.$scoped.withValue(modelSettings) {
            configureWindowEngines()
        }
    }

    func reloadAssistantConfiguration() {
        let targets = application?.windows.filter { $0.browser.context === browser.context } ?? [self]
        targets.forEach { $0.configureEngines() }
    }

    private func configureWindowEngines() {
        linkPeek.canPreviewPullRequests = { [weak self] in
            guard let self else { return false }
            return settings.showsGitHub && github.canPreview
        }
        linkPeek.previewPullRequest = { [weak self] reference in
            await self?.github.preview(reference)
        }
        linkPeek.makeModel = { [weak self] in
            guard let self else { return UtilityModelSource.onDevice() }
            let selected = modelProviders.resolve(selectedProvider)
            if let model = selected.makeUtilityModel(
                model: modelSettings.model(for: selected.configuration)
            ) {
                return model
            }
            return UtilityModelSource.onDevice()
        }
        let toolkit = AgentToolkit(
            browser: browser,
            media: media,
            log: conversationLog,
            questions: agentQuestions
        )
        agentTurns.onCancel = { [weak self] in self?.agentQuestions.abandon() }
        selectedProvider = ProviderCatalog.shared.selected
        selectedModel = LLMSettings.model(for: selectedProvider)
        selectedEffort = ReasoningCatalog.resolve(
            LLMSettings.reasoningEffort(for: selectedProvider),
            for: selectedProvider,
            model: selectedModel
        )

        let selected = modelProviders.resolve(selectedProvider)
        supportsReasoningEffort = selected.capabilities.contains(.reasoning)
        let onDeviceFallback = modelProviders.resolve(ProviderCatalog.appleOnDevice)
        let hostedFallback = modelProviders.resolve(ProviderCatalog.openAI)
        let decision = AgentProviderSelection.decide(
            selected: AgentProviderCandidate(
                configuration: selected.configuration,
                availability: selected.availability
            ),
            onDeviceFallback: AgentProviderCandidate(
                configuration: onDeviceFallback.configuration,
                availability: onDeviceFallback.availability
            ),
            hostedFallback: AgentProviderCandidate(
                configuration: hostedFallback.configuration,
                availability: hostedFallback.availability
            )
        )

        func use(_ provider: any ModelProvider) {
            let configuration = provider.configuration
            let built = provider.makeAgent(
                model: LLMSettings.model(for: configuration),
                reasoningEffort: LLMSettings.reasoningEffort(for: configuration),
                toolkit: toolkit,
                log: conversationLog
            )
            built.prepare()
            agentTurns.use(built)
            activeProvider = configuration
            isUsingSelectedProvider = configuration.id == selectedProvider.id
        }

        func unavailable() {
            agentTurns.use(nil)
            activeProvider = nil
            isUsingSelectedProvider = false
        }

        switch decision {
        case .use(let configuration, let notice):
            use(modelProviders.resolve(configuration))
            activeNotice = notice
        case .unavailable(let message):
            activeNotice = message
            unavailable()
        }
        statusMessage = selected.availability == .needsCredentials ? nil : activeNotice
        configureRemoteTools(for: activeProvider ?? selectedProvider)
        configureVoice()
        Pipeline.log.notice("Assistant engine configured")
        discoverContextWindow()
    }

    func followSettings() {
        let profileID = browser.context.profile.id
        github.announce = { update in
            NotificationBridge.shared.post(
                title: update.pr.title, subtitle: "\(update.pr.repository.nameWithOwner) #\(update.pr.number)",
                body: update.summary, identifier: "github-\(update.pr.id)", link: update.pr.url,
                profileID: profileID
            )
        }
        NotificationBridge.shared.linkOpener = { [weak application] url, profileID in
            guard let application, let profileID,
                  let profile = ProfileStore.shared.profiles.first(where: { $0.id == profileID }) else { return }
            let windows = application.windows.filter { $0.profiles.current.id == profileID }
            let window = windows.first { $0.isKeyWindow } ?? windows.last ?? application.newWindow(profile: profile)
            window.showBrowser()
            window.openGitHubLink(url)
        }
        if !AppDatabase.isRunningTests, settings.showsGitHub {
            github.start()
        }
        let context = browser.context
        let targets: () -> [AppCoordinator] = { [weak context, weak application, weak self] in
            guard let context else { return [] }
            return application?.windows.filter { $0.browser.context === context }
                ?? self.map { [$0] } ?? []
        }
        settings.onWebPreferencesChanged = {
            targets().forEach { $0.browser.applyWebSettings() }
        }
        settings.onAppearanceChanged = {
            targets().forEach { $0.updateWindowAppearance() }
        }
        settings.onMediaPlayerChanged = { isOn in
            targets().forEach { $0.media.isEnabled = isOn }
        }
        settings.onAutomaticPictureInPictureChanged = { _ in
            targets().forEach { $0.applyPictureLending() }
        }
        settings.onVideoInPlayerChanged = { _ in
            targets().forEach { $0.applyPictureLending() }
        }
        settings.onLyricsChanged = { isOn in
            targets().forEach { $0.sidePanel.setAvailable(isOn, for: .lyrics) }
        }
        settings.onArchiveTabsAfterChanged = { _ in
            targets().forEach { $0.browser.archiveStaleTabs() }
        }
        settings.onGitHubChanged = { [weak context] isOn in
            targets().forEach { $0.sidePanel.setAvailable(isOn, for: .github) }
            guard !AppDatabase.isRunningTests, let github = context?.github else { return }
            if isOn {
                github.start()
            } else {
                github.stop()
            }
        }
        media.isEnabled = settings.showsMediaPlayer
        applyPictureLending()
        sidePanel.setAvailable(settings.showsLyrics, for: .lyrics)
        sidePanel.setAvailable(settings.showsGitHub, for: .github)
        updateWindowAppearance()
        browser.downloads.webViewProvider = {
            let windows = targets()
            return (windows.first { $0.isKeyWindow } ?? windows.last)?.browser.activeTab?.webView
        }
        browser.downloads.onFinished = { filename in
            let windows = targets()
            (windows.first { $0.isKeyWindow } ?? windows.last)?
                .show(notice: String(localized: "Downloaded \(filename)"))
        }
        browser.downloads.onBegin = {
            targets().first { $0.isKeyWindow }?.downloadFlights.launch()
        }
    }

    private func startUpdates() {
        updates.setChannel(settings.updateChannel)
        settings.onUpdateChannelChanged = { [weak self] channel in
            self?.updates.setChannel(channel)
        }
        updates.start()
    }

    private func discoverContextWindow() {
        guard let provider = activeProvider, !provider.isOnDevice else { return }
        let context = browser.context
        let modelSettings = context.modelSettings
        let model = modelSettings.model(for: provider)
        guard !model.isEmpty,
              modelSettings.discoveredContextWindow(for: provider, model: model) == nil
        else { return }
        Task { [weak self] in
            guard let window = await ProviderContextProbe().effectiveWindow(
                    for: provider, model: model, apiKey: CredentialStore.key(for: provider)
                  ),
                  window != modelSettings.discoveredContextWindow(for: provider, model: model)
            else { return }
            modelSettings.setDiscoveredContextWindow(window, for: provider, model: model)
            Pipeline.log.notice("Model context window discovered")
            guard let self, browser.context === context, !isClosed else { return }
            reloadAssistantConfiguration()
        }
    }

    // MARK: - Key monitors

    private func installKeyMonitors() {
        installEscapeHandler()
        installTabSwitchHandler()
        installDownloadFlights()
    }

    private func installDownloadFlights() {
        downloadFlights.watchClicks { [weak self] in self?.nativeWindow }
        browser.downloads.apply(settings.downloadRetention)
    }

    private func installTabSwitchHandler() {
        guard tabSwitchMonitor == nil else { return }
        tabSwitchMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.isKeyWindow else { return }
                self.tabSwitchModifiersChanged(event)
                self.noteLinkModifiers(event.modifierFlags)
            }
            return event
        }
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.browser.endTabSwitching()
            }
        }
    }

    private func tabSwitchModifiersChanged(_ event: NSEvent) {
        let flags = event.modifierFlags
        guard flags.contains(.control) else {
            shiftStep.cancel()
            browser.endTabSwitching()
            return
        }
        guard event.keyCode == 56 || event.keyCode == 60 else { return }
        if flags.contains(.shift) {
            shiftStep.shiftDown(whileSwitching: browser.isSwitchingTabs)
        } else if shiftStep.shiftUp(), browser.isSwitchingTabs {
            browser.switchTab(forward: false)
        }
    }

    func noteLinkModifiers(_ flags: NSEvent.ModifierFlags) {
        let wanted = flags.intersection([.command, .shift])
        guard wanted != linkModifiers else { return }
        linkModifiers = wanted
    }

    private func installEscapeHandler() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            var claimed = false
            MainActor.assumeIsolated {
                claimed = self?.handleKey(event) ?? false
            }
            return claimed ? nil : event
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard isKeyWindow else { return false }
        if browser.isSwitchingTabs {
            switch event.keyCode {
            case 53:
                browser.cancelTabSwitching()
                return true
            case 36, 76:
                browser.endTabSwitching()
                return true
            default:
                break
            }
        }
        if let responder = nativeWindow?.firstResponder, responder is NSText {
            return false
        }
        if peek.isOpen,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "o" {
            keepPeek()
            return true
        }
        guard event.keyCode == 53 else { return false }
        return handleEscape()
    }

    private func handleEscape() -> Bool {
        guard isKeyWindow else { return false }
        if let responder = nativeWindow?.firstResponder, responder is NSText {
            return false
        }
        if onboarding.isPresented {
            onboarding.finish()
            return true
        }
        if isProfileSwitcherOpen {
            isProfileSwitcherOpen = false
            return true
        }
        if closePeek() {
            return true
        }
        let closedInspector = sidePanel.close()
        if conversationVoice?.isActive == true || state == .listening || state == .executing {
            voiceInput.cancel()
            stopAgent()
            return true
        }
        if isAgentSpeaking {
            speech.stopSpeaking()
            return true
        }
        if let tab = browser.activeTab, tab.isLoading {
            tab.stopLoading()
            return true
        }
        return closedInspector
    }
}

private struct BootstrapTiming {
    private let start = ContinuousClock.now
    private var last: ContinuousClock.Instant?
    private var phases: [String] = []

    mutating func mark(_ phase: String) {
        let now = ContinuousClock.now
        phases.append("\(phase) \((now - (last ?? start)).milliseconds)ms")
        last = now
    }

    func log() {
        let total = (ContinuousClock.now - start).milliseconds
        let detail = phases.joined(separator: ", ")
        Pipeline.log.notice("bootstrap: done in \(total, privacy: .public)ms, \(detail, privacy: .public)")
    }
}
