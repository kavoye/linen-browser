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
    let engine = EngineSelection()

    let browser: BrowserModel
    var github: GitHubPanelModel {
        browser.context.github
    }
    var extensions: ExtensionManager {
        browser.context.extensions
    }
    weak var application: BrowserApplication?
    var windowID: UUID {
        browser.windowID
    }
    var nativeWindow: NSWindow? {
        host?.nativeWindow
    }
    var isKeyWindow: Bool {
        nativeWindow?.isKeyWindow == true
    }
    var pointerInShell: CGPoint? {
        guard let window = nativeWindow, let content = window.contentView else { return nil }
        let location = window.mouseLocationOutsideOfEventStream
        return CGPoint(x: location.x, y: content.bounds.height - location.y)
    }
    var isBootstrapped = false
    private(set) var isClosed = false
    let media: MediaCenter
    #if DEBUG
    let lyrics = LyricsModel(defaults: StageMode.defaults)
    #else
    let lyrics = LyricsModel()
    #endif
    var conversationLog: ConversationLog {
        browser.context.conversationLog
    }
    let downloadFlights = DownloadFlights()
    let agentQuestions = AgentQuestionModel()
    var agentReply: AgentReplyModel {
        agentTurns.reply
    }
    private let standaloneUpdates = UpdateController()
    var updates: UpdateController {
        application?.updates ?? standaloneUpdates
    }
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
    let githubPreview = GitHubPreviewPresenter()
    let linkPeek = LinkPeek()
    let peek = PeekPanel()
    let sidebarDrag = SidebarDragModel()
    let translationDownloads = TranslationDownloads()
    @ObservationIgnored private(set) lazy var settingsWorkspace: SettingsWorkspace = {
        let workspace = SettingsWorkspace(coordinator: self)
        workspace.onRoute = { [weak self] category, path, isBack in
            self?.routeSettings(to: category, path: path, isBack: isBack)
        }
        return workspace
    }()
    var settings: BrowserSettings {
        browser.context.settings
    }
    var modelSettings: LLMSettings {
        browser.context.modelSettings
    }

    var mcpServer: BrowserMCPServer {
        application?.mcpServer ?? standaloneMCPServer
    }
    @ObservationIgnored private lazy var standaloneMCPServer = BrowserMCPServer(
        browser: browser, defaults: BrowserMCPServer.appDefaults,
        canListen: { [weak self] in
            guard let self else { return false }
            return !profiles.isPrivate && !isSwitchingProfile
        }
    ) { [weak self] in
        guard let self else { return false }
        return !profiles.isPrivate && !isSwitchingProfile && !agentTurns.isRunning
    }

    let voiceConversation = VoiceConversationState()
    let voiceRoute = VoiceRoute()
    let voicePreview = VoicePreviewPlayer()
    let answerSpeech = AnswerSpeechState()
    let voiceInput: VoiceInputModel
    let speech: ProviderSpeechOutput
    let readerSpeech = ReaderVoice()
    let readerListener: ReaderListener
    @ObservationIgnored var remoteToolConfigurationID: String?
    let agentTurns: AgentTurnModel
    let activation: any ActivationSource = HoldToTalkMonitor()
    let modelProviders: any ModelProviderResolving

    #if DEBUG
    let attention = AgentAttention(defaults: StageMode.defaults)
    #else
    let attention = AgentAttention()
    #endif
    let memoryPressure = MemoryPressureMonitor()
    let archiveSweeper = TabArchiveSweeper()
    private var host: BrowserHost?
    var mainMenu: MainMenu?

    @ObservationIgnored private var isAskingForMicrophone = false
    @ObservationIgnored private var shellFrameInWindow: CGRect = .zero
    var frozenShellSize: CGSize?
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?
    @ObservationIgnored private var iconScheme = FaviconLoader.shared.scheme

    private var queuedExternalURLs: [URL] = []
    private var readyForExternalLinks = false

    private(set) var browserVisible = false
    private(set) var windowControlsInset: CGFloat = 0
    private(set) var addressBarFocusToken = 0
    let palette = PalettePresentation()
    let overlays = ShellOverlays()
    let notice = ChromeNotice()
    var sidebarDestination: SidebarDestination? {
        SidebarDestination.resolve(activeTabID: browser.activeTab?.id)
    }

    let voicePreferences = VoicePreferences.shared
    var voicePreferencesObserver: NSObjectProtocol?

    var isSpeechMuted: Bool {
        !voicePreferences.speaksAnswers
    }

    init(
        browser: BrowserModel = BrowserModel(),
        profiles: ProfileStore? = nil,
        modelProviders: any ModelProviderResolving = ModelProviderRegistry()
    ) {
        self.browser = browser
        self.profiles = profiles ?? ProfileStore.selection(profile: browser.context.profile)
        self.modelProviders = modelProviders
        let extensions = browser.context.extensions
        extensions.register(browser: browser)
        media = MediaCenter()

        voiceInput = VoiceInputModel()
        speech = ProviderSpeechOutput()
        readerListener = ReaderListener(output: readerSpeech)
        agentTurns = AgentTurnModel(
            browser: browser,
            log: browser.context.conversationLog,
            speech: speech,
            modelSettings: browser.context.modelSettings,
            actionPolicy: browser.context.actionPolicy
        )
        speech.isMuted = !voicePreferences.speaksAnswers
        voicePreferencesObserver = NotificationCenter.default.addObserver(
            forName: VoicePreferences.didChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyVoicePreferences()
            }
        }
        speech.onSpeakingChange = { [weak self] speaking in
            guard let self else { return }
            answerSpeech.speakingChanged(speaking)
            agentSpeechChanged(speaking)
        }
        connectReaderListener()
        voiceInput.onWillBegin = { [weak self] in
            guard let self else { return }
            endVoiceConversation()
            speech.stopSpeaking()
            readerListener.stop()
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
            Pipeline.log.notice("Voice request received")
            runAgent(with: utterance, trace: trace)
        }
        agentTurns.onTurnFinished = { [weak self] in
            self?.voiceInput.clearTranscript()
            self?.statusMessage = nil
        }

        configureWindowCallbacks()
        configureWindowAgentTransfer()

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
        overlays.onCoverChange = { [weak self] in self?.applyHoverShield() }
        observeAppearance()
    }

    private func observeAppearance() {
        appearanceObservation = NSApp?.observe(\.effectiveAppearance) { @Sendable [weak self] _, _ in
            Task { @MainActor [weak self] in self?.reloadFaviconsIfSchemeChanged() }
        }
    }

    func reloadFaviconsIfSchemeChanged() {
        let scheme = browser.context.favicons.scheme
        guard scheme != iconScheme else { return }
        iconScheme = scheme
        for tab in browser.tabs {
            tab.refreshFavicon()
        }
    }

    func noteShellFrame(_ frame: CGRect) {
        guard frame != shellFrameInWindow else { return }
        shellFrameInWindow = frame
        applyHoverShield()
    }

    var windowMinimumWidth: CGFloat {
        BrowserWindowMetrics.minWidth(
            dockedSidebarWidth: sidebar.dockedWidth,
            isPanelVisible: sidePanel.isVisible
        )
    }

    func updateWindowMinimum() {
        host?.setMinimumWidth(windowMinimumWidth)
    }

    func applyHoverShield() {
        let shellFrame = shellFrameInWindow
        guard shellFrame.width > 0 else { return }
        let width = sidebar.openWidth(in: shellFrame.width)
        let besideSidebar = shellFrame.width - (sidebar.isVisible ? width : 0)
        let shell = LoomShellGeometry(
            containerWidth: shellFrame.width,
            sidebarWidth: width,
            preferredPanelWidth: sidePanel.openWidth(in: besideSidebar),
            isSidebarVisible: sidebar.isVisible,
            isPanelVisible: sidePanel.isVisible,
            isPanelExpanded: sidePanel.isVisible && sidePanel.isExpanded
        )
        let peeked = shownPeek?.webView
        for view in TabWebView.liveInstances.allObjects {
            guard view.window === nativeWindow else { continue }
            guard view.window != nil else {
                view.setHoverParked(false)
                continue
            }
            // A page under the peek must not answer the pointer: hover reaches
            // it through its own tracking areas, whatever is drawn on top.
            if let peeked, view !== peeked {
                view.setHoverParked(true)
                continue
            }
            let viewMaxX = view.convert(view.bounds, to: nil).maxX - shellFrame.minX
            view.setHoverParked(
                SidebarPeekShield.suppressesHover(
                    isVisible: sidebar.isVisible,
                    isPeeking: sidebar.isPeeking,
                    viewMaxX: viewMaxX,
                    width: width,
                    isMediaPicture: view === media.model.pictureWebView
                )
                    || shell.panelCoversPage
                    || overlays.isPointerOnPageCover
            )
        }
    }

    func toggleSpeechMute() {
        voicePreferences.speaksAnswers.toggle()
    }

    func applyVoicePreferences() {
        let mutes = isSpeechMuted && !speech.isMuted
        speech.isMuted = isSpeechMuted
        if mutes {
            speech.stopSpeaking()
        }
        if !voicePreferences.allowsConversation, voiceConversation.isPresented || voiceConversation.session != nil {
            endVoiceConversation()
        }
        configureVoice()
    }

    func stopAgentSpeech() {
        endVoiceConversation()
        speech.stopSpeaking()
        answerSpeech.clear()
    }

    var isSpeakingInChrome: Bool {
        agentReply.isStreaming && agentReply.showsInChrome(inSpace: browser.activeSpaceID)
    }

    func pendingAgentQuestion(inChrome: Bool) -> AgentQuestionModel.Ask? {
        let spaceID = browser.activeSpaceID
        guard agentReply.showsInChrome(inSpace: spaceID) == inChrome else { return nil }
        return agentQuestions.ask(inSpace: spaceID)
    }

    func readAloud(_ text: String, id: UUID) {
        endVoiceConversation()
        guard !text.isEmpty else { return }
        readerListener.stop()
        let stopsCurrent = answerSpeech.speakingAnswerID == id
        speech.stopSpeaking()
        answerSpeech.clear()
        guard !stopsCurrent else { return }
        answerSpeech.begin(id)
        let muted = speech.isMuted
        speech.isMuted = false
        speech.speak(text)
        speech.isMuted = muted
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
    @ObservationIgnored var shiftStep = ShiftStep()
    var resignActiveObserver: NSObjectProtocol?

    // MARK: - Profiles

    let profiles: ProfileStore

    var switchingTo: Profile?

    var isSwitchingProfile: Bool {
        switchingTo != nil
    }

    var privateSession: PrivateBrowsingSession?

    let profileSwitches = SerialTasks()

    // MARK: - Presentation

    func showBrowser(activate: Bool = true) {
        guard !isClosed else { return }
        ensureHost().show(activate: activate)
        updateWindowAppearance()
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

    let mediaDock = MediaDockState()

    var linkModifiers: NSEvent.ModifierFlags = []

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
        addressBarFocusToken += 1
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
        guard browser.history.count > 0 else { return }
        Task {
            guard let choice = await ConfirmAlert.clear(.history()) else { return }
            await BrowsingData.clear(choice.kinds, range: choice.range, history: browser.history, context: browser.context)
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
        let titles = loose.map { ($0.id, $0.title) }
        Task { [weak self, activity = browser.modelActivity] in
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

    func closeAskingIfPinned(_ tab: BrowserTab, then closed: @escaping () -> Void = {}) {
        guard tab.pinnedURL != nil else {
            browser.close(tab)
            closed()
            return
        }
        Task {
            guard await ConfirmAlert.destructive(
                "Close this pinned tab?",
                detail: "Closing this tab also removes its pin. You can pin the page again later.",
                verb: "Close Tab"
            ) else { return }
            browser.close(tab)
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

    func hostDidChange(visible: Bool, controlsInset: CGFloat) {
        browserVisible = visible
        windowControlsInset = controlsInset
    }

    func prepareWindowBloom() {
        ensureHost().seedBloom()
    }

    func growWindowAfterOnboarding() {
        host?.growToOpeningFrame()
    }

    private func ensureHost() -> BrowserHost {
        if let host {
            return host
        }
        let created = BrowserHost(coordinator: self)
        host = created
        return created
    }

    func releaseWindowHost() {
        host = nil
    }

    func beginClosingWindow() -> Bool {
        guard !isClosed else { return false }
        isClosed = true
        return true
    }

    // MARK: - Voice input

    static let speechNotReadyMessage = String(localized: "Speech recognition is starting. Try again shortly.")

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
            if granted, voiceConversation.isPresented {
                statusMessage = nil
                startVoiceConversation()
            } else if granted {
                statusMessage = String(localized: "Hold \(ActivationSettings.talk.phrase) again to speak.")
            } else {
                statusMessage = Self.microphoneDeniedMessage
                if voiceConversation.isPresented {
                    voiceConversation.message = statusMessage
                }
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

    @discardableResult
    private func runAgent(
        with utterance: String,
        mentionedTabIDs: [UUID] = [],
        attachments: [AssistantAttachment] = [],
        attachmentTextOnly: Bool = false,
        trace: LatencyTrace?,
        showsInChrome: Bool = true
    ) -> Bool {
        mcpServer.cancelActiveCall()
        let started = agentTurns.run(
            utterance: utterance,
            mentionedTabIDs: mentionedTabIDs,
            attachments: attachments,
            attachmentTextOnly: attachmentTextOnly,
            trace: trace,
            showsInChrome: showsInChrome
        )
        guard started else {
            statusMessage = "Add an API key for \(engine.selectedProvider.name) in Settings, or enable Apple Intelligence."
            voiceInput.clearTranscript()
            return false
        }
        return true
    }

    // MARK: - Typed input

    func continueAgent() {
        endVoiceConversation()
        voiceInput.cancel()
        speech.stopSpeaking()
        mcpServer.cancelActiveCall()
        agentTurns.run(utterance: "", isContinuation: true, showsInChrome: false)
    }

    @discardableResult
    func handleTypedUtterance(
        _ raw: String,
        mentionedTabIDs: [UUID] = [],
        attachments: [AssistantAttachment] = [],
        showsInChrome: Bool = true
    ) async -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachmentTextOnly = !ModelImageSupport.acceptsImages(for: engine.selectedProvider, model: engine.selectedModel)
        guard !text.isEmpty || !attachments.isEmpty else { return false }
        do {
            try AttachmentRequest.validate(
                attachments, message: text, textOnly: attachmentTextOnly,
                windowTokens: ContextWindow.tokens(for: engine.selectedProvider, model: engine.selectedModel)
            )
        } catch {
            statusMessage = error.localizedDescription
            return false
        }

        endVoiceConversation()
        voiceInput.cancel()
        speech.stopSpeaking()
        agentTurns.cancel()
        Pipeline.log.notice("Typed request received")
        return runAgent(
            with: text.isEmpty ? String(localized: "Read the attached files.") : text,
            mentionedTabIDs: mentionedTabIDs,
            attachments: attachments,
            attachmentTextOnly: attachmentTextOnly,
            trace: LatencyTrace(),
            showsInChrome: showsInChrome
        )
    }
}
