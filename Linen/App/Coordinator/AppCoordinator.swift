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
    let status = TimedStatus(lifetime: .seconds(12))
    var statusMessage: String? {
        get { status.message }
        set { status.message = newValue }
    }
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

    private(set) var browser: BrowserModel
    @ObservationIgnored let activeBrowser: ActiveTabModel
    @ObservationIgnored var parkedModels: [UUID: BrowserModel] = [:]
    @ObservationIgnored let spaceStore: SpaceStore
    @ObservationIgnored private(set) lazy var spaceSlider = SpaceSlideController(coordinator: self)

    func show(_ model: BrowserModel) {
        browser = model
        activeBrowser.model = model
    }
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
    func makeExternalToolkit() -> AgentToolkit {
        AgentToolkit(browser: browser, media: media, log: conversationLog)
    }

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
        following: { [weak self] in self?.browser }, defaults: BrowserMCPServer.appDefaults,
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

    @ObservationIgnored var isAskingForMicrophone = false
    @ObservationIgnored private var shellFrameInWindow: CGRect = .zero
    var frozenShellSize: CGSize?
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?
    @ObservationIgnored private var iconScheme = FaviconLoader.shared.scheme

    @ObservationIgnored private var externalLinks = ExternalLinkQueue()

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
        spaceStore: SpaceStore = .shared,
        modelProviders: any ModelProviderResolving = ModelProviderRegistry()
    ) {
        self.browser = browser
        self.spaceStore = spaceStore
        activeBrowser = ActiveTabModel(browser)
        self.profiles = profiles ?? ProfileStore.selection(profile: browser.context.profile)
        self.modelProviders = modelProviders
        let extensions = browser.context.extensions
        extensions.register(browser: browser)
        media = MediaCenter()

        voiceInput = VoiceInputModel()
        speech = ProviderSpeechOutput()
        readerListener = ReaderListener(output: readerSpeech)
        agentTurns = AgentTurnModel(
            browser: activeBrowser,
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
        bindTabModel(browser)

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

    func requestAddressBarFocus() {
        addressBarFocusToken += 1
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
        agentReply.isStreaming && agentReply.showsInChrome(inAnchor: browser.activeAnchorID)
    }

    func pendingAgentQuestion(inChrome: Bool) -> AgentQuestionModel.Ask? {
        let anchorID = browser.activeAnchorID
        guard agentReply.showsInChrome(inAnchor: anchorID) == inChrome else { return nil }
        return agentQuestions.ask(inAnchor: anchorID)
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
        guard let web = externalLinks.accept(urls) else { return }
        showBrowser()
        for url in web {
            openNewTab(url: url)
        }
    }

    func drainQueuedExternalURLs() {
        openFromAnotherApp(externalLinks.open())
    }

    let mediaDock = MediaDockState()

    var linkModifiers: NSEvent.ModifierFlags = []

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
}
