// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import os
import WebKit

extension AppCoordinator {
    // MARK: - Launch

    func bootstrap() async {
        Pipeline.log.notice("bootstrap: begin")
        OutputDucker.restoreAfterUncleanExit()
        settings.applyAppearance()
        followSettings()
        applyProfileStores(profiles.current)
        extensions.useLibrary(for: profiles.current)
        memoryPressure.onPressure = { [weak self] level in
            self?.browser.relieveMemoryPressure(level)
        }
        memoryPressure.start()
        browser.downloads.onFinished = { [weak self] filename in
            self?.show(notice: String(localized: "Downloaded \(filename)"))
        }
        let menu = MainMenu(coordinator: self)
        menu.install()
        mainMenu = menu
        ContentBlocker.shared.refresh()
        WebViewPool.shared.prepare(
            scriptSource: MediaCenter.frameScriptSource,
            handlerName: MediaCenter.frameScriptHandlerName,
            handler: media.frameScriptHandler
        )
        WebViewPool.shared.addScript(
            GeolocationBridge.scriptSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            handlerName: GeolocationBridge.handlerName,
            handler: GeolocationBridge.shared
        )
        WebViewPool.shared.addScript(
            NotificationBridge.scriptSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            handlerName: NotificationBridge.handlerName,
            handler: NotificationBridge.shared
        )
        GeolocationBridge.shared.tabResolver = { [weak self] webView in
            self?.browser.tabs.first { $0.isMaterialised && $0.webView === webView }
        }
        NotificationBridge.shared.tabResolver = { [weak self] webView in
            self?.browser.tabs.first { $0.isMaterialised && $0.webView === webView }
        }
        WebViewPool.shared.installExtensionController(extensions.controller)
        WebViewPool.shared.warmUp()
        browser.restoreSession()
        retainAgentMemory()
        wireMedia()
        let notifyExtensions = browser.onActiveTabChanged
        browser.onActiveTabChanged = { [weak self] newTab, previousTab in
            notifyExtensions?(newTab, previousTab)
            self?.followMedia(to: newTab, from: previousTab)
            self?.applyHoverShield()
        }
        browser.onSpaceAnchorChanged = { [weak self] from, to in
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
        linkPeek.begin()
        onboarding.beginIfNeeded()
        if onboarding.isPresented {
            prepareWindowBloom()
        }
        showBrowser()
        if onboarding.isPresented {
            bloomWindowOpen()
        }
        if !AppDatabase.ownsSession {
            show(notice: String(localized: "Another copy of Linen is open. Nothing here is saved."))
        }
        drainQueuedExternalURLs()

        startUpdates()
        MoveToApplications.reregisterDefaultBrowserIfNeeded()
        Task { [weak self] in
            guard let self, await releaseNotes.shouldOpenForNewVersion() else { return }
            showReleaseNotes()
        }

        extensions.onOpenTab = { [weak self] url in
            self?.openNewTab(url: url)
        }
        Task { [extensions] in
            await extensions.start()
            await extensions.updateInstalledIfDue()
        }

        activation.onPress = { [weak self] in
            guard let self, !onboarding.isPresented, microphoneIsReady() else { return }
            voiceInput.begin()
        }
        activation.onRelease = { [weak self] in
            guard let self, !onboarding.isPresented else { return }
            voiceInput.scheduleFinish()
        }
        activation.start()
        installKeyMonitors()

        configureEngines()

        do {
            try await voiceInput.prepare()
            Pipeline.log.notice("bootstrap: transcriber ready")
            if statusMessage == Self.speechNotReadyMessage {
                statusMessage = nil
            }
        } catch {
            statusMessage = String(localized: "Couldn’t set up speech: \(error.localizedDescription)")
            Pipeline.log.error("Transcriber prepare failed: \(error, privacy: .public)")
        }

        Pipeline.log.notice("bootstrap: done")
    }

    func engine(for configuration: Provider) -> any ModelProvider {
        modelProviders.resolve(configuration)
    }

    func configureEngines() {
        UtilityModelSource.make = { [weak self] in
            guard let self else { return UtilityModelSource.onDevice() }
            let selected = modelProviders.resolve(ProviderCatalog.shared.selected)
            if let model = selected.makeUtilityModel(
                model: LLMSettings.model(for: selected.configuration)
            ) {
                return model
            }
            return UtilityModelSource.onDevice()
        }
        let toolkit = AgentToolkit(
            browser: browser,
            media: media,
            log: conversationLog,
            extensionController: extensions.controller,
            preview: researchPreview,
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

        func unavailable(_ why: String) {
            agentTurns.use(nil)
            activeProvider = nil
            isUsingSelectedProvider = false
            statusMessage = why
        }

        switch decision {
        case .use(let configuration, let notice):
            use(modelProviders.resolve(configuration))
            activeNotice = notice
            statusMessage = notice
        case .unavailable(let message):
            activeNotice = message
            unavailable(message)
        }
        Pipeline.log.notice("agent engine = \(self.agentName, privacy: .public)")
        discoverLocalContextWindow()
    }

    private func followSettings() {
        settings.onWebPreferencesChanged = { [weak self] in
            self?.browser.applyWebSettings()
        }
        media.isEnabled = settings.showsMediaPlayer
        settings.onMediaPlayerChanged = { [weak self] isOn in
            self?.media.isEnabled = isOn
        }
        applyPictureLending()
        settings.onAutomaticPictureInPictureChanged = { [weak self] _ in
            self?.applyPictureLending()
        }
        settings.onVideoInPlayerChanged = { [weak self] _ in
            self?.applyPictureLending()
        }
        sidePanel.setAvailable(settings.showsLyrics, for: .lyrics)
        settings.onLyricsChanged = { [weak self] isOn in
            self?.sidePanel.setAvailable(isOn, for: .lyrics)
        }
    }

    private func startUpdates() {
        updates.setChannel(settings.updateChannel)
        settings.onUpdateChannelChanged = { [weak self] channel in
            self?.updates.setChannel(channel)
        }
        updates.start()
    }

    private func discoverLocalContextWindow() {
        guard let provider = activeProvider, provider.isLocal, !provider.isOnDevice else { return }
        let model = LLMSettings.model(for: provider)
        Task { [weak self] in
            guard let window = await OllamaContextProbe().effectiveWindow(for: provider, model: model),
                  window != LLMSettings.discoveredContextWindow(for: provider, model: model)
            else { return }
            LLMSettings.setDiscoveredContextWindow(window, for: provider, model: model)
            Pipeline.log.notice("context window for \(model, privacy: .public) = \(window)")
            self?.configureEngines()
        }
    }

    // MARK: - Key monitors

    private func installKeyMonitors() {
        installEscapeHandler()
        installTabSwitchHandler()
        installDownloadFlights()
    }

    private func installDownloadFlights() {
        downloadFlights.watchClicks { NSApp.keyWindow ?? NSApp.mainWindow }
        PageClickWatcher.shared.onClick = { [weak self] point in
            self?.downloadFlights.noteClick(at: point)
        }
        browser.downloads.apply(settings.downloadRetention)
        browser.downloads.onBegin = { [weak self] in
            self?.downloadFlights.launch()
        }
    }

    private func installTabSwitchHandler() {
        guard tabSwitchMonitor == nil else { return }
        tabSwitchMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated {
                self?.controlChanged(isDown: event.modifierFlags.contains(.control), at: event.timestamp)
                self?.noteLinkModifiers(event.modifierFlags)
            }
            return event
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.controlChanged(isDown: false, at: ProcessInfo.processInfo.systemUptime)
            }
        }
    }

    func noteLinkModifiers(_ flags: NSEvent.ModifierFlags) {
        let wanted = flags.intersection([.command, .shift])
        guard wanted != linkModifiers else { return }
        linkModifiers = wanted
    }

    private func controlChanged(isDown: Bool, at timestamp: TimeInterval) {
        guard isDown else {
            controlDownAt = nil
            browser.endTabSwitching()
            return
        }
        if controlDownAt == nil {
            controlDownAt = timestamp
        }
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
        if let responder = NSApp.keyWindow?.firstResponder, responder is NSText {
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
        if let responder = NSApp.keyWindow?.firstResponder, responder is NSText {
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
        if state == .listening || state == .executing {
            voiceInput.cancel()
            stopAgent()
            return true
        }
        if isAgentSpeaking {
            speech.stopSpeaking()
            return true
        }
        if let tab = browser.activeTab, tab.isLoading {
            tab.webView.stopLoading()
            return true
        }
        return closedInspector
    }
}
