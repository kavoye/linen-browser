// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Observation
import os
import WebKit

@MainActor
@Observable
final class AppCoordinator {
    var state: PipelineState {
        if voiceInput.phase != .idle {
            return voiceInput.pipelineState
        }
        return agentTurns.isRunning ? .executing : .idle
    }

    var liveTranscript: String {
        voiceInput.transcript
    }
    var statusMessage: String? {
        didSet {
            statusFadeTask?.cancel()
            statusFadeTask = nil
            guard statusMessage != nil else { return }
            statusFadeTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled else { return }
                self?.statusMessage = nil
            }
        }
    }
    @ObservationIgnored private var statusFadeTask: Task<Void, Never>?
    var agentName: String {
        agentTurns.runnerName
    }

    static func displayAgentName(for name: String) -> String {
        name == "none" ? String(localized: "Assistant") : name
    }

    var agentDisplayName: String {
        Self.displayAgentName(for: agentName)
    }
    var isUsingSelectedProvider = true

    var activeProvider: Provider?
    var activeNotice: String?

    var selectedProvider = ProviderCatalog.openAI
    var selectedModel = ""
    var selectedEffort = LLMSettings.reasoningEffort
    var supportsReasoningEffort = false

    let browser = BrowserModel()
    let extensions: ExtensionManager
    let media: MediaCenter
    #if DEBUG
    let lyrics = LyricsModel(defaults: StageMode.defaults)
    #else
    let lyrics = LyricsModel()
    #endif
    let conversationLog = ConversationLog()
    let downloadFlights = DownloadFlights()
    let agentQuestions = AgentQuestionModel()
    var agentReply: AgentReplyModel {
        agentTurns.reply
    }
    let updates = UpdateController()
    let releaseNotes = ReleaseNotesModel()
    #if DEBUG
    let onboarding = OnboardingModel(defaults: StageMode.defaults)
    #else
    let onboarding = OnboardingModel()
    #endif
    let sidebar = SidebarLayout()
    #if DEBUG
    let sidePanel = SidePanelModel(defaults: StageMode.defaults)
    #else
    let sidePanel = SidePanelModel()
    #endif
    let tabPreview = TabPreviewModel()
    let sidebarDrag = SidebarDragModel()
    let researchPreview = ResearchPreview()
    let settings = BrowserSettings.shared

    let voiceInput: VoiceInputModel
    let speech: any SpeechOutput
    let agentTurns: AgentTurnModel
    let activation: any ActivationSource = HoldToTalkMonitor()
    let modelProviders: any ModelProviderResolving

    #if DEBUG
    let attention = AgentAttention(defaults: StageMode.defaults)
    #else
    let attention = AgentAttention()
    #endif
    let memoryPressure = MemoryPressureMonitor()
    private var host: BrowserHost?
    var mainMenu: MainMenu?

    @ObservationIgnored private var isAskingForMicrophone = false
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?
    @ObservationIgnored private var iconScheme = FaviconLoader.shared.scheme

    private var queuedExternalURLs: [URL] = []
    private var readyForExternalLinks = false

    private(set) var browserVisible = false
    private(set) var windowControlsInset: CGFloat = 0
    private(set) var addressBarFocusToken = 0
    private(set) var isPaletteOpen = false
    var isProfileSwitcherOpen = false
    var profileButtonFrame: CGRect?
    private(set) var paletteToken = 0
    var sidebarDestination: SidebarDestination? {
        SidebarDestination.resolve(activeTabID: browser.activeTab?.id)
    }

    private(set) var notice: String?
    private var noticeToken = 0

    private(set) var isSpeechMuted: Bool
    private static let speechMutedKey = "speech.muted"
    private(set) var isAgentSpeaking = false

    init(modelProviders: any ModelProviderResolving = ModelProviderRegistry()) {
        self.modelProviders = modelProviders
        let extensions = ExtensionManager(browser: browser)
        self.extensions = extensions
        media = MediaCenter()

        voiceInput = VoiceInputModel()
        speech = AppleSpeechOutput()
        agentTurns = AgentTurnModel(
            browser: browser,
            log: conversationLog,
            speech: speech
        )
        isSpeechMuted = Self.initialSpeechMuted(
            stored: UserDefaults.standard.object(forKey: Self.speechMutedKey)
        )
        speech.isMuted = isSpeechMuted
        speech.onSpeakingChange = { [weak self] speaking in
            self?.isAgentSpeaking = speaking
        }
        voiceInput.onWillBegin = { [weak self] in
            guard let self else { return }
            speech.stopSpeaking()
            agentTurns.cancel()
        }
        voiceInput.onFailure = { [weak self] failure in
            self?.handleVoiceFailure(failure)
        }
        voiceInput.onUtterance = { [weak self] utterance, trace in
            guard let self else {
                trace.end()
                return
            }
            Pipeline.log.notice("utterance: \"\(utterance, privacy: .private)\"")
            runAgent(with: utterance, trace: trace)
        }
        agentTurns.onTurnFinished = { [weak self] in
            self?.voiceInput.clearTranscript()
            self?.statusMessage = nil
        }
        browser.downloads.webViewProvider = { [weak self] in self?.browser.activeTab?.webView }

        let extensionTabClosed = browser.onTabClosed
        browser.onTabClosed = { [weak self] tab in
            extensionTabClosed?(tab)
            self?.tabDidClose(tab)
        }

        sidebarDrag.planSource = { [weak self] in
            guard let self else { return SplitDropPlan() }
            let frame = sidebarDrag.contentFrameInWindow
            guard frame.width > 0, frame.height > 0 else { return SplitDropPlan() }
            if let split = browser.activeSplit {
                return SplitDropPlan(
                    grid: split,
                    size: frame.size,
                    gutter: SplitMetrics.gutter,
                    carrying: sidebarDrag.carriedPaneID
                )
            }
            if let tab = browser.activeTab {
                return SplitDropPlan(singlePage: tab.id, size: frame.size)
            }
            return SplitDropPlan()
        }

        sidebar.onShowingChange = { [weak self] in self?.applyHoverShield() }
        sidePanel.onFootprintChange = { [weak self] in self?.applyHoverShield() }
        TabWebView.refreshHoverShield = { [weak self] in self?.applyHoverShield() }
        observeAppearance()
    }

    private func observeAppearance() {
        appearanceObservation = NSApp?.observe(\.effectiveAppearance) { @Sendable _, _ in
            Task { @MainActor [weak self] in self?.reloadFaviconsIfSchemeChanged() }
        }
    }

    func reloadFaviconsIfSchemeChanged() {
        let scheme = FaviconLoader.shared.scheme
        guard scheme != iconScheme else { return }
        iconScheme = scheme
        for tab in browser.tabs {
            tab.refreshFavicon()
        }
    }

    func applyHoverShield() {
        let content = sidebarDrag.contentFrameInWindow
        let width = sidebar.openWidth(in: content.width)
        let shell = LoomShellGeometry(
            containerWidth: content.width,
            sidebarWidth: width,
            preferredPanelWidth: sidePanel.openWidth(in: content.width),
            isSidebarVisible: false,
            isPanelVisible: sidePanel.isVisible,
            isPanelExpanded: sidePanel.isExpanded
        )
        for view in TabWebView.liveInstances.allObjects {
            guard view.window != nil else {
                view.setHoverParked(false)
                continue
            }
            let viewMaxX = view.convert(view.bounds, to: nil).maxX
            view.setHoverParked(
                SidebarPeekShield.suppressesHover(
                    isVisible: sidebar.isVisible,
                    isPeeking: sidebar.isPeeking,
                    viewMaxX: viewMaxX,
                    width: width,
                    isMediaPicture: view === media.model.pictureWebView
                )
                    || shell.panelCoversPage(viewMaxX: viewMaxX - content.minX)
            )
        }
    }

    private func tabDidClose(_ tab: BrowserTab) {
        playedPages[tab.id] = nil
        FaviconTint.forget(tab.id)
        if media.controlledTabID == tab.id {
            media.releaseControl()
            dockSuccessor(to: tab.id)
        }
        if agentTurns.closeTab(tab.id) {
            voiceInput.clearTranscript()
            statusMessage = nil
        }
    }

    var targetTab: BrowserTab? {
        if let tabID = agentTurns.activeTabID,
           let tab = browser.tabs.first(where: { $0.id == tabID }) {
            return tab
        }
        return browser.activeTab
    }

    nonisolated static func initialSpeechMuted(stored: Any?) -> Bool {
        stored as? Bool ?? true
    }

    func toggleSpeechMute() {
        isSpeechMuted.toggle()
        UserDefaults.standard.set(isSpeechMuted, forKey: Self.speechMutedKey)
        speech.isMuted = isSpeechMuted
        if isSpeechMuted {
            speech.stopSpeaking()
        }
    }

    func stopAgentSpeech() {
        speech.stopSpeaking()
    }

    var isSpeakingInChrome: Bool {
        agentReply.isStreaming && agentReply.showsInChrome(inSpace: browser.activeSpaceID)
    }

    func readAloud(_ text: String) {
        guard !text.isEmpty else { return }
        if isAgentSpeaking {
            speech.stopSpeaking()
            return
        }
        let muted = speech.isMuted
        speech.isMuted = false
        speech.speak(text)
        speech.isMuted = muted
    }

    func clearDataOnQuitIfNeeded() async {
        guard settings.clearsDataOnQuit else { return }
        await BrowsingData.clearEverything(
            history: browser.history,
            agent: conversationLog,
            tabs: browser.tabs
        )
    }

    func reloadActivation() {
        activation.reload()
    }

    func setActivationSuspended(_ suspended: Bool) {
        activation.setSuspended(suspended)
    }

    // MARK: - Escape

    var escapeMonitor: Any?

    // MARK: - Tab switching

    var tabSwitchMonitor: Any?

    var controlDownAt: TimeInterval?

    var isControlTap: Bool {
        let now = NSApp.currentEvent?.timestamp ?? ProcessInfo.processInfo.systemUptime
        return ModifierTap.isTap(downAt: controlDownAt, now: now)
    }

    // MARK: - Profiles

    let profiles = ProfileStore.shared

    var switchingTo: Profile?

    var isSwitchingProfile: Bool {
        switchingTo != nil
    }

    var privateSession: PrivateBrowsingSession?

    var hasPrivateSession: Bool {
        privateSession != nil
    }

    let profileSwitches = SerialTasks()

    // MARK: - Presentation

    var browserIsFrontmost: Bool {
        browserVisible && NSApp.isActive
    }

    func showBrowser() {
        ensureHost().show()
    }

    func openFromAnotherApp(_ urls: [URL]) {
        let web = urls.filter { $0.scheme == "http" || $0.scheme == "https" || $0.isFileURL }
        guard !web.isEmpty else { return }
        guard readyForExternalLinks else {
            queuedExternalURLs.append(contentsOf: web)
            return
        }
        showBrowser()
        for url in web {
            openNewTab(url: url)
        }
    }

    func drainQueuedExternalURLs() {
        readyForExternalLinks = true
        let queued = queuedExternalURLs
        queuedExternalURLs = []
        openFromAnotherApp(queued)
    }

    func openSettings(_ category: SettingsCategory? = nil) {
        showBrowser()
        let tab = browser.showSettings()
        guard let category else { return }
        route(to: category, in: tab)
    }

    func routeSettings(to category: SettingsCategory) {
        guard let tab = browser.tabs.first(where: { $0.internalPage == .settings }) else { return }
        route(to: category, in: tab)
    }

    private func route(to category: SettingsCategory, in tab: BrowserTab) {
        let url = SystemPages.settingsURL(category)
        guard tab.urlString != url.absoluteString else { return }
        tab.load(url)
        tab.urlString = url.absoluteString
        tab.title = BrowserTab.InternalPage.settings.title
    }

    var isShowingSettings: Bool {
        browser.activeTab?.internalPage == .settings
    }

    // MARK: - Media following the tab you're looking at

    var mediaClaim = 0
    var playedPages: [UUID: String] = [:]
    var lyricsPinnedTabID: UUID?

    func togglePin() {
        guard let tab = browser.activeTab else { return }
        if tab.isShowingPin {
            browser.unpin(tab)
        } else {
            browser.pin(tab)
        }
    }

    func printActivePage() {
        guard let webView = browser.activeTab?.webView else { return }
        PagePrinting.begin(for: webView)
    }

    func toggleFullScreen() {
        (NSApp.keyWindow ?? NSApp.mainWindow)?.toggleFullScreen(nil)
    }

    func copyCurrentURL() {
        guard let tab = browser.activeTab else { return }
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
        let notice: LocalizedStringResource = urls.count == 1 ? "Link Copied" : "Links Copied"
        show(notice: String(localized: notice))
    }

    func linkURL(for tab: BrowserTab) -> URL? {
        guard !tab.urlString.isEmpty,
              let url = (tab.isMaterialised ? tab.webView.url : nil) ?? URL(string: tab.urlString),
              url.scheme != "about", !SystemPages.isStart(url)
        else { return nil }
        return url
    }

    func show(notice message: String) {
        notice = message
        noticeToken += 1
        let token = noticeToken
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard noticeToken == token else { return }
            notice = nil
        }
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

    func focusAddressBar() {
        if !browserVisible {
            showBrowser()
        }
        addressBarFocusToken += 1
    }

    func openPalette() {
        showBrowser()
        paletteToken += 1
        isPaletteOpen = true
    }

    func togglePalette() {
        if isPaletteOpen, browserIsFrontmost {
            closePalette()
            return
        }
        openPalette()
    }

    func closePalette() {
        isPaletteOpen = false
    }

    func confirmClearHistory() {
        guard browser.history.count > 0 else { return }
        Task {
            guard let choice = await ConfirmAlert.clear(.history()) else { return }
            await BrowsingData.clear(choice.kinds, range: choice.range, history: browser.history)
        }
    }

    func organizeTabs() {
        guard TabOrganizer.isAvailable else {
            statusMessage = String(localized: "Organizing tabs needs a model: add a provider key or enable Apple Intelligence.")
            return
        }
        let loose = browser.tabs.filter {
            browser.folder(containing: $0) == nil && $0.pinnedURL == nil
        }
        guard loose.count >= 4 else {
            statusMessage = String(localized: "Not enough loose tabs to organize.")
            return
        }
        statusMessage = String(localized: "Looking for related tabs…")
        Task { [weak self] in
            let outcome = await TabOrganizer.propose(for: loose.map { ($0.id, $0.title) })
            guard let self else { return }
            statusMessage = nil
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
            let proposed = plan.folders.map { ($0.name, $0.tabIDs.count) }
            guard await ConfirmAlert.organize(folders: proposed) else { return }
            for folder in plan.folders {
                let members = folder.tabIDs
                    .compactMap { id in browser.tabs.first { $0.id == id } }
                    .filter { browser.folder(containing: $0) == nil && $0.pinnedURL == nil }
                guard members.count >= 2 else { continue }
                let made = browser.createFolder(named: folder.name, containing: members)
                if browser.tabs(in: made).count < 2 {
                    Pipeline.log.error("organized folder arrived empty; removing it")
                    browser.deleteFolder(made)
                }
            }
        }
    }

    func closeAskingIfBookmarked(_ tab: BrowserTab) {
        guard tab.pinnedURL != nil else {
            browser.close(tab)
            return
        }
        Task {
            guard await ConfirmAlert.destructive(
                "Close this bookmarked tab?",
                detail: "Its bookmark is removed when the tab closes.",
                verb: "Close Tab"
            ) else { return }
            browser.close(tab)
        }
    }

    func closeActiveTabAskingIfBookmarked() {
        guard let tab = browser.activeTab else { return }
        closeAskingIfBookmarked(tab)
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

    func toggleAgentInspector() {
        if !browserVisible {
            showBrowser()
        }
        sidePanel.toggle(.activity)
    }

    func toggleSidebar() {
        if !browserVisible {
            showBrowser()
        }
        sidebar.toggleVisible()
    }

    func useProvider(_ provider: Provider) {
        guard provider.id != selectedProvider.id else { return }
        ProviderCatalog.shared.select(provider)
        configureEngines()
    }

    func stopAgent() {
        agentTurns.cancel()
        speech.stopSpeaking()
    }

    func toggleMicListening() {
        if voiceInput.phase == .listening {
            Task { await voiceInput.finish() }
        } else if microphoneIsReady() {
            voiceInput.begin(endsOnSilence: true)
        }
    }

    func hostDidChange(visible: Bool, controlsInset: CGFloat) {
        browserVisible = visible
        windowControlsInset = controlsInset
    }

    private func ensureHost() -> BrowserHost {
        if let host {
            return host
        }
        let created = BrowserHost(coordinator: self)
        host = created
        return created
    }

    // MARK: - Voice input

    static let speechNotReadyMessage = String(localized: "The speech engine is still warming up.")

    static let microphoneDeniedMessage = String(
        localized: "Allow Linen to use the microphone under Privacy & Security > Microphone."
    )

    func microphoneIsReady() -> Bool {
        switch MicrophoneAccess.state {
        case .allowed:
            return true
        case .undecided:
            askForMicrophone()
            return false
        case .denied:
            statusMessage = Self.microphoneDeniedMessage
            MicrophoneAccess.openSystemSettings()
            return false
        }
    }

    private func askForMicrophone() {
        guard !isAskingForMicrophone else { return }
        isAskingForMicrophone = true
        Task { [weak self] in
            let granted = await MicrophoneAccess.request()
            guard let self else { return }
            isAskingForMicrophone = false
            if granted {
                statusMessage = String(localized: "Hold \(ActivationSettings.talk.phrase) again to speak.")
            } else {
                statusMessage = Self.microphoneDeniedMessage
            }
        }
    }

    private func handleVoiceFailure(_ failure: VoiceInputModel.Failure) {
        switch failure {
        case .notReady:
            statusMessage = Self.speechNotReadyMessage
        case .capture(let description):
            statusMessage = String(localized: "Couldn’t start the microphone: \(description)")
        case .transcription:
            statusMessage = String(localized: "Couldn’t transcribe the recording.")
        }
    }

    private func runAgent(
        with utterance: String,
        mentionedTabIDs: [UUID] = [],
        trace: LatencyTrace?,
        showsInChrome: Bool = true
    ) {
        let started = agentTurns.run(
            utterance: utterance,
            mentionedTabIDs: mentionedTabIDs,
            trace: trace,
            showsInChrome: showsInChrome
        )
        guard started else {
            statusMessage = "Add an API key for \(ProviderCatalog.shared.selected.name) in Settings, or enable Apple Intelligence."
            voiceInput.clearTranscript()
            return
        }
    }

    // MARK: - Typed input

    func handleTypedUtterance(
        _ raw: String,
        mentionedTabIDs: [UUID] = [],
        showsInChrome: Bool = true
    ) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        voiceInput.cancel()
        speech.stopSpeaking()
        agentTurns.cancel()
        Pipeline.log.notice("typed utterance: \"\(text, privacy: .private)\"")
        runAgent(
            with: text,
            mentionedTabIDs: mentionedTabIDs,
            trace: LatencyTrace(),
            showsInChrome: showsInChrome
        )
    }
}
