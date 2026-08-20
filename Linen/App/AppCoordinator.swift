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
    enum Page: Equatable {
        case browser
        case settings
    }

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
    let conversationLog = ConversationLog()
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
    let agentInspector = InspectorLayout(defaults: StageMode.defaults)
    #else
    let agentInspector = InspectorLayout()
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
    private(set) var paletteToken = 0
    private(set) var page: Page = .browser {
        didSet {
            guard oldValue != page else { return }
            browser.sidebarSelection.dropMarks()
        }
    }

    var sidebarDestination: SidebarDestination? {
        SidebarDestination.resolve(page: page, activeTabID: browser.activeTab?.id)
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
        let width = sidebar.openWidth(in: sidebarDrag.contentFrameInWindow.width)
        for view in TabWebView.liveInstances.allObjects {
            guard view.window != nil else {
                view.setHoverParked(false)
                continue
            }
            view.setHoverParked(SidebarPeekShield.suppressesHover(
                isVisible: sidebar.isVisible,
                isPeeking: sidebar.isPeeking,
                viewMaxX: view.convert(view.bounds, to: nil).maxX,
                width: width,
                isMediaPicture: view === media.model.pictureWebView
            ))
        }
    }

    private func tabDidClose(_ tab: BrowserTab) {
        playedPages[tab.id] = nil
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

    // MARK: - Profiles

    let profiles = ProfileStore.shared

    var isSwitchingProfile = false

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

    func hideBrowser() {
        host?.hide()
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

    func toggleBrowser() {
        ensureHost().toggle()
    }

    var settingsDestination: SettingsCategory?

    func openSettings(_ category: SettingsCategory? = nil) {
        showBrowser()
        page = .settings
        if let category {
            settingsDestination = category
        }
    }

    func showBrowserPage() {
        page = .browser
    }

    // MARK: - Media following the tab you're looking at

    var mediaClaim = 0
    var playedPages: [UUID: String] = [:]

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
        guard page == .browser, let tab = browser.activeTab else { return }
        copyLink(for: tab)
    }

    func copyLink(for tab: BrowserTab) {
        guard let url = linkURL(for: tab) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        pasteboard.setString(url.absoluteString, forType: .string)
        show(notice: String(localized: "Link Copied"))
    }

    func linkURL(for tab: BrowserTab) -> URL? {
        guard tab.internalPage == nil, !tab.urlString.isEmpty,
              let url = tab.webView.url ?? URL(string: tab.urlString),
              url.scheme != "about"
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
        showBrowserPage()
    }

    func focusPane(_ tab: BrowserTab) {
        guard browser.activeTabID != tab.id, browser.isVisibleInSplit(tab) else { return }
        browser.activate(tab)
    }

    @discardableResult
    func openNewTab(url: URL? = nil) -> BrowserTab {
        let tab = browser.newTab(url: url)
        showBrowserPage()
        return tab
    }

    func focusAddressBar() {
        if !browserVisible {
            showBrowser()
        }
        showBrowserPage()
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

    func showHistory() {
        showBrowser()
        showBrowserPage()
        browser.showHistory()
    }

    func showDownloads() {
        showBrowser()
        showBrowserPage()
        browser.showDownloads()
    }

    func toggleAgentInspector() {
        if !browserVisible {
            showBrowser()
        }
        showBrowserPage()
        agentInspector.toggle()
    }

    func toggleSidebar() {
        if !browserVisible {
            showBrowser()
        }
        sidebar.toggleVisible()
    }

    func toggleMicListening() {
        if voiceInput.phase == .listening {
            Task { await voiceInput.finish() }
        } else if microphoneIsReady() {
            voiceInput.begin()
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

    private func runAgent(with utterance: String, mentionedTabIDs: [UUID] = [], trace: LatencyTrace?) {
        guard agentTurns.run(utterance: utterance, mentionedTabIDs: mentionedTabIDs, trace: trace) else {
            statusMessage = "Add an API key for \(ProviderCatalog.shared.selected.name) in Settings, or enable Apple Intelligence."
            voiceInput.clearTranscript()
            return
        }
    }

    // MARK: - Typed input

    func handleTypedUtterance(_ raw: String, mentionedTabIDs: [UUID] = []) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        voiceInput.cancel()
        speech.stopSpeaking()
        agentTurns.cancel()
        Pipeline.log.notice("typed utterance: \"\(text, privacy: .private)\"")
        runAgent(with: text, mentionedTabIDs: mentionedTabIDs, trace: LatencyTrace())
    }
}
