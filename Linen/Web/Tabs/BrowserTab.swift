// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Observation
import os
import SwiftUI
import WebKit

@MainActor
@Observable
final class BrowserTab: Identifiable {
    static let placeholderTitle = String(localized: "New Page")

    let id: UUID
    let autofillSave = AutofillSaveSession()
    var pageTitle = BrowserTab.placeholderTitle
    var customTitle = ""
    private var documentTitles: [URL: String] = [:]

    var title: String {
        get { customTitle.isEmpty ? pageTitle : customTitle }
        set { pageTitle = newValue }
    }
    var urlString = ""
    @ObservationIgnored var lastActiveAt = Date()
    var isLoading = false
    var isShowingError = false
    var favicon: NSImage?
    private var faviconHost = ""
    var progress: Double = 0
    var pageColor: NSColor?
    var isRestoring = false
    var isPlayingAudio = false
    var hasVideo = false
    var isPictureOut = false
    var isAgentWorking: Bool {
        processState.isAgentWorking
    }
    var isMuted = false
    var hasNoPageYet: Bool {
        urlString.isEmpty && !isLoading
    }

    private(set) var hoveredLink: URL?

    func noteHoveredLink(
        _ url: URL?,
        modifiers: NSEvent.ModifierFlags = [],
        at anchor: CGPoint = .zero
    ) {
        onLinkHovered?(url, modifiers, anchor)
        guard hoveredLink != url else { return }
        hoveredLink = url
    }

    private var canGoBackInWeb = false
    private var canGoForwardInWeb = false

    var isShowingStartPage: Bool {
        SystemPages.isStart(committedURL)
    }

    var canGoBack: Bool {
        _ = canGoBackInWeb
        guard isMaterialised else { return false }
        return webView.canGoBack
    }

    var canGoForward: Bool {
        _ = canGoForwardInWeb
        guard isMaterialised else { return false }
        return webView.canGoForward
    }

    /// `urlString` may include a provisional navigation; this URL reflects the committed page.
    private(set) var committedURL: URL?

    var isUnderTopBar = false {
        didSet {
            guard isUnderTopBar != oldValue, isMaterialised else { return }
            Self.applyObscuredInsets(to: webView, isUnderTopBar: isUnderTopBar)
            measureBandUnderBar()
        }
    }

    var isControlledByMediaDock = false

    private(set) var preview: NSImage?

    func refreshPreview() {
        guard isMaterialised, isShowingRealPage, !isDeferred, webView.window != nil else { return }
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = 480
        configuration.afterScreenUpdates = false
        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            guard let image else { return }
            self?.preview = image
        }
    }

    private(set) var canvasColor: NSColor?

    /// Page background shown before the web view presents and during pull gestures.
    var surfaceColor: Color {
        canvasColor.map(Color.init(nsColor:)) ?? Theme.windowBackground
    }

    private(set) var hasPresentedContent = false

    private(set) var security: PageSecurity = .none

    var internalPage: InternalPage? {
        if let addressed = InternalPage(url: URL(string: urlString)) {
            return addressed
        }
        if isMaterialised, !isLoading, let standing = webView.url {
            return InternalPage(url: standing)
        }
        return InternalPage(url: committedURL)
    }

    var isShowingSystemPage: Bool {
        internalPage != nil || isShowingStartPage
    }

    /// Only permit internal navigation to the `linen:` URL requested by the app.
    private var permittedSystemPage: URL?

    func permitSystemPage(_ url: URL?) {
        permittedSystemPage = SystemPages.isSystem(url) ? url : nil
    }

    func permitsSystemPage(_ url: URL) -> Bool {
        permittedSystemPage == url
    }

    // MARK: - The pin

    var pinnedURL: URL?
    var pinnedTitle = ""

    var isAwayFromPin: Bool {
        guard let pinnedURL else { return false }
        return !urlString.isEmpty && urlString != pinnedURL.absoluteString
    }

    var isShowingPin: Bool {
        guard let pinnedURL else { return false }
        return urlString == pinnedURL.absoluteString
    }
    @ObservationIgnored private var liveView: WKWebView?
    private var webViewGeneration = 0
    @ObservationIgnored private var stoppedNavigation = false

    var isMaterialised: Bool {
        liveView != nil
    }

    var webView: WKWebView {
        _ = webViewGeneration
        if let liveView {
            return liveView
        }
        let view = self.context.webViewPool.makeColdView()
        liveView = view
        adopt(view)
        return view
    }
    var onNavigationStarted: ((URL) -> Void)?
    var onNavigationFinished: ((Bool) -> Void)?
    var onNavigationOutsideExtension: ((URL) -> Void)?
    var onNewWindow: ((WKWebView, Bool) -> Void)?
    var onOpenInNewTab: ((URL, Bool) -> Void)?
    var onOpenInNewWindow: ((URL, Bool) -> Void)?
    var onOpenInPeek: ((URL, CGPoint) -> Void)?
    var onSummarizeLink: ((URL, CGPoint) -> Void)?
    var onCloseRequested: (() -> Void)?
    var onPictureInPictureChanged: ((Bool) -> Void)?
    var onPictureReturnExpected: (() -> Void)?
    var onDownload: ((WKDownload, URL?) -> Void)?
    var onSaveDocument: ((Data, String, URL?, Bool) async -> Void)?
    var onLinkHovered: ((URL?, NSEvent.ModifierFlags, CGPoint) -> Void)?

    let extensionBaseURL: URL?
    let popups: TabPopupPolicy
    let externalApps: TabExternalAppPolicy

    private var navigationDelegate: TabNavigationDelegate?
    let permissions: TabPermissionCenter
    let assistantAccess: TabAssistantAccessCenter
    let find = FindSession()
    let reader = ReaderSession()
    @ObservationIgnored var isFrontmost = false {
        didSet {
            if isFrontmost, !oldValue {
                probeReader()
            }
        }
    }
    let translation = PageTranslation()

    let isPrivate: Bool
    let context: BrowserProfileContext

    private var progressObservation: NSKeyValueObservation?
    private var loadingObservation: NSKeyValueObservation?
    private var cameraObservation: NSKeyValueObservation?
    private var microphoneObservation: NSKeyValueObservation?
    private var pageBackgroundObservation: NSKeyValueObservation?
    private var addressObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?
    private var backObservation: NSKeyValueObservation?
    private var forwardObservation: NSKeyValueObservation?
    private var fullscreenObservation: NSKeyValueObservation?
    private var secureContentObservation: NSKeyValueObservation?
    private let processState = TabProcessState()
    var provisionalNavigation: WKNavigation?
    var committedNavigation: WKNavigation?

    init(
        id: UUID = UUID(),
        extensionHost: ExtensionPageHost? = nil,
        adopting: WKWebView? = nil,
        restoring: Bool = false,
        opensBlank: Bool = true,
        privately: Bool = false,
        sitePermissions: SitePermissions = .shared,
        context: BrowserProfileContext? = nil
    ) {
        self.id = id
        self.context = context ?? .shared(for: privately ? .privateBrowsing() : .original())
        isPrivate = privately
        popups = TabPopupPolicy(store: sitePermissions, settings: self.context.settings)
        externalApps = TabExternalAppPolicy(store: sitePermissions, isPrivate: privately)
        permissions = TabPermissionCenter(store: sitePermissions)
        assistantAccess = TabAssistantAccessCenter(store: sitePermissions)
        permissions.persistsAnswers = !privately
        assistantAccess.persistsAnswers = !privately
        let opensStartPage = opensBlank && adopting == nil && extensionHost == nil && !restoring
        if opensStartPage {
            pageTitle = SystemPages.startTitle
        }
        if let adopting {
            // WebKit requires this exact view, with the opener's configuration attached.
            liveView = adopting
            extensionBaseURL = nil
        } else if let extensionHost {
            liveView = self.context.webViewPool.makeView(configuration: extensionHost.configuration)
            extensionBaseURL = extensionHost.baseURL
            pageTitle = extensionHost.name
            favicon = extensionHost.icon
        } else {
            liveView = restoring ? nil : self.context.webViewPool.acquire()
            extensionBaseURL = nil
        }
        if let liveView {
            adopt(liveView)
        }
        find.driver = .webKit { [weak self] in self?.reader.presentedView ?? self?.webView }
        reader.driver = .webKit { [weak self] in
            guard let self, isMaterialised else { return nil }
            return webView
        }
        if opensStartPage {
            permitSystemPage(SystemPages.start)
            webView.load(URLRequest(url: SystemPages.start))
        }
    }

    private func adopt(_ view: WKWebView) {
        (view as? TabWebView)?.profileContext = context
        liveView = view
        Self.applyObscuredInsets(to: webView, isUnderTopBar: isUnderTopBar)
        fullscreenObservation = webView.observe(\.fullscreenState, options: [.new]) { [weak self] view, _ in
            MainActor.assumeIsolated {
                Self.applyObscuredInsets(to: view, isUnderTopBar: self?.isUnderTopBar ?? true)
            }
        }

        let delegate = TabNavigationDelegate(tab: self)
        navigationDelegate = delegate
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        (webView as? TabWebView)?.onContextDownload = { [weak self] download, source in
            self?.onDownload?(download, source)
        }
        (webView as? TabWebView)?.onOpenLinkInNewWindow = { [weak self] url, isPrivate in
            self?.onOpenInNewWindow?(url, isPrivate)
        }
        (webView as? TabWebView)?.onPeekLink = { [weak self] url in
            guard let self else { return }
            onOpenInPeek?(url, TabNavigationDelegate.pointer(in: webView))
        }
        (webView as? TabWebView)?.onSummarizeLink = { [weak self] url, anchor in
            guard let self else { return }
            onSummarizeLink?(url, anchor ?? TabNavigationDelegate.pointer(in: webView))
        }
        if let tabView = webView as? TabWebView {
            tabView.onPageActivity = { [weak self] signal in
                self?.notePageActivity(signal)
            }
            PageActivityMonitor.shared.install(in: tabView)
            tabView.onScrollPosition = { [weak self] y, url in
                self?.lastReportedScrollY = y
                self?.lastReportedScrollURL = url
            }
            ScrollPositionMonitor.shared.install(in: tabView)
            tabView.onFaviconDeclarationChange = { [weak self] in
                self?.declaredFaviconChanged()
            }
            FaviconWatcher.shared.install(in: tabView)
            PageClickWatcher.shared.install(in: tabView)
            tabView.onPopupBlocked = { [weak self] url in
                self?.popups.note(url)
            }
            SiteContentGuard.shared.install(in: tabView)
            PaymentCardAutofill.shared.install(in: tabView, profileID: context.profile.id)
            ContactAutofill.shared.install(in: tabView, profileID: context.profile.id)
            PasswordAutofill.shared.install(in: tabView, profileID: context.profile.id)
            AutofillSaveCoordinator.shared.install(in: tabView, session: autofillSave, profileID: context.profile.id)
        }
        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
            let value = change.newValue ?? 1
            MainActor.assumeIsolated {
                self?.progress = value
            }
        }
        loadingObservation = webView.observe(\.isLoading, options: [.new, .initial]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refreshChrome() }
        }
        addressObservation = webView.observe(\.url, options: [.new]) { [weak self] view, _ in
            MainActor.assumeIsolated { self?.pageDidChangeInPlace(view) }
        }
        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refreshChrome() }
        }
        backObservation = webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refreshChrome() }
        }
        forwardObservation = webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refreshChrome() }
        }
        secureContentObservation = webView.observe(
            \.hasOnlySecureContent,
            options: [.new]
        ) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refreshSecurity() }
        }
        pageBackgroundObservation = webView.observe(
            \.underPageBackgroundColor,
            options: [.new, .initial]
        ) { [weak self] view, _ in
            MainActor.assumeIsolated {
                self?.refreshCanvas(from: view)
                self?.measureBandUnderBar()
            }
        }
        cameraObservation = webView.observe(\.cameraCaptureState, options: [.new, .initial]) { [weak self] view, _ in
            MainActor.assumeIsolated {
                self?.permissions.setLive(.camera, view.cameraCaptureState != .none)
            }
        }
        microphoneObservation = webView.observe(\.microphoneCaptureState, options: [.new, .initial]) { [weak self] view, _ in
            MainActor.assumeIsolated {
                self?.permissions.setLive(.microphone, view.microphoneCaptureState != .none)
            }
        }
        permissions.onRevoke = { [weak self] permission in
            guard let self else { return }
            switch permission {
            case .camera:
                webView.setCameraCaptureState(.none)
            case .microphone:
                webView.setMicrophoneCaptureState(.none)
            case .location:
                onLocationRevoked?()
            case .notifications:
                break
            }
        }
        permissions.pageChanged(url: webView.url ?? (urlString.isEmpty ? nil : URL(string: urlString)))
        assistantAccess.pageChanged(url: webView.url ?? (urlString.isEmpty ? nil : URL(string: urlString)))
        applySiteZoom()
        applySitePopups()
        (webView as? TabWebView)?.onZoomChanged = { [weak self] in
            self?.zoomDidChange()
        }
    }

    // MARK: - Discarding

    var canDiscardWebContent: Bool {
        guard !isDeferred, intrinsicProtectionReason == nil else { return false }
        return !urlString.isEmpty
    }

    var intrinsicProtectionReason: TabProtectionReason? {
        processState.protectionReason(
            isPrivate: isPrivate,
            isExtensionPage: extensionBaseURL != nil,
            hasDeviceAccess: !permissions.live.isEmpty,
            hasMediaPlayback: isControlledByMediaDock || isPlayingAudio
        )
    }

    var hasEditedForm: Bool {
        processState.hasEditedForm
    }
    var isSharingScreen: Bool {
        processState.isSharingScreen
    }

    func setAgentWorking(_ isWorking: Bool) {
        processState.setAgentWorking(isWorking)
    }

    func setExternalAutomationWorking(_ isWorking: Bool) {
        processState.isExternalAutomationWorking = isWorking
    }

    func notePageActivity(_ signal: PageActivitySignal) {
        processState.notePageActivity(signal)
    }

    func clearPageActivity() {
        processState.clearPageActivity()
    }

    func discardWebContent() {
        guard canDiscardWebContent else { return }
        unloadUntilShown()
    }

    private func unloadUntilShown() {
        guard let outgoing = liveView else { return }
        let state = sessionState
        let url = URL(string: urlString)
        guard state != nil || url != nil else { return }

        retire(outgoing)
        stoppedNavigation = false

        // Keep the session and create a replacement view when the tab becomes visible.
        liveView = nil
        hasPresentedContent = false
        deferRestore(state: state, url: url)
        processState.markUnloaded()
    }

    private func retire(_ outgoing: WKWebView) {
        outgoing.stopLoading()
        outgoing.navigationDelegate = nil
        outgoing.uiDelegate = nil
        (outgoing as? TabWebView)?.onZoomChanged = nil
        (outgoing as? TabWebView)?.onContextDownload = nil
        (outgoing as? TabWebView)?.onOpenLinkInNewWindow = nil
        (outgoing as? TabWebView)?.onPeekLink = nil
        (outgoing as? TabWebView)?.onSummarizeLink = nil
        (outgoing as? TabWebView)?.onPageActivity = nil
        (outgoing as? TabWebView)?.onScrollPosition = nil
        (outgoing as? TabWebView)?.onFaviconDeclarationChange = nil
        (outgoing as? TabWebView)?.onPopupBlocked = nil
        outgoing.removeFromSuperview()
        progressObservation = nil
        loadingObservation = nil
        cameraObservation = nil
        microphoneObservation = nil
        pageBackgroundObservation = nil
        addressObservation = nil
        titleObservation = nil
        backObservation = nil
        forwardObservation = nil
        fullscreenObservation = nil
        secureContentObservation = nil
        permissions.onRevoke = nil
        navigationDelegate = nil
    }

    func stopLoading() {
        webView.stopLoading()
        stoppedNavigation = true
        isLoading = false
    }

    func noteNavigationStarted() {
        stoppedNavigation = false
    }

    func reload() {
        let wasStopped = stoppedNavigation
        if wasStopped && webView.isLoading && extensionBaseURL == nil
            && URL(string: urlString) != nil {
            restartPage()
            return
        }
        stoppedNavigation = false
        if let url = URL(string: urlString),
           webView.backForwardList.currentItem == nil || (wasStopped && url != committedURL) {
            load(url, transition: .reload)
            return
        }
        if webView.reload() == nil, extensionBaseURL == nil {
            restartPage()
        }
    }

    func showWebInspector() {
        let accessor = NSSelectorFromString("_inspector")
        let show = NSSelectorFromString("show")
        guard webView.responds(to: accessor),
              let inspector = webView.perform(accessor)?.takeUnretainedValue() as? NSObject,
              inspector.responds(to: show)
        else { return }
        inspector.perform(show)
    }

    /// Replace an unresponsive WebKit view without closing the tab or its data store.
    func restartPage() {
        guard !isClosed, extensionBaseURL == nil,
              let url = URL(string: urlString), let outgoing = liveView
        else { return }
        onContentProcessTerminated?()
        retire(outgoing)
        stoppedNavigation = false
        provisionalNavigation = nil
        committedNavigation = nil
        isRestoring = false
        isLoading = false
        progress = 0
        hasPresentedContent = false
        isShowingError = false
        isPlayingAudio = false
        hasVideo = false
        isPictureOut = false
        committedURL = nil
        pendingTransition = .reload
        clearPageActivity()
        invalidateSessionState()
        processState.finishReload()
        releasePageColorHold()

        let replacement = self.context.webViewPool.makeColdView(
            dataStore: outgoing.configuration.websiteDataStore
        )
        adopt(replacement)
        webViewGeneration &+= 1
        permitSystemPage(url)
        if url.isFileURL {
            replacement.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            replacement.load(URLRequest(url: url))
        }
    }

    var onLocationRevoked: (() -> Void)?

    private func pageDidChangeInPlace(_ webView: WKWebView) {
        let previous = urlString
        if !SystemPages.isStart(webView.url) {
            permissions.pageChanged(url: webView.url)
            assistantAccess.pageChanged(url: webView.url)
        }
        applySiteZoom()
        applySitePopups()
        refreshChrome()
        guard urlString != previous else { return }
        refreshPageColor(from: webView)
        refreshFavicon()
        measureBandUnderBar()
        invalidateSessionState()
        readerPageMoved(from: previous)
        translationPageMoved()
        onSameDocumentNavigation?()
    }

    var onSameDocumentNavigation: (() -> Void)?

    var onContentProcessTerminated: (() -> Void)?
    var isShown: (() -> Bool)?

    private(set) var isClosed = false

    func detach() {
        guard !isClosed else { return }
        isClosed = true
        reader.close()
        onNavigationStarted = nil
        onNavigationFinished = nil
        onNavigationOutsideExtension = nil
        onNewWindow = nil
        onOpenInNewTab = nil
        onOpenInNewWindow = nil
        onOpenInPeek = nil
        onSummarizeLink = nil
        onCloseRequested = nil
        onPictureInPictureChanged = nil
        onPictureReturnExpected = nil
        onDownload = nil
        onSaveDocument = nil
        onLinkHovered = nil
        onSameDocumentNavigation = nil
        onContentProcessTerminated = nil
        isShown = nil
        onLocationRevoked = nil
        navigationDelegate = nil
        if translation.isActive, let liveView {
            translation.showOriginal(in: liveView)
        }
        translation.documentChanged()
        guard let view = liveView else { return }
        view.navigationDelegate = nil
        view.uiDelegate = nil
        (view as? TabWebView)?.onContextDownload = nil
        (view as? TabWebView)?.onOpenLinkInNewWindow = nil
        (view as? TabWebView)?.onPeekLink = nil
        (view as? TabWebView)?.onSummarizeLink = nil
        (view as? TabWebView)?.onZoomChanged = nil
    }

    func contentProcessDidTerminate() {
        guard !isClosed else { return }
        isPlayingAudio = false
        onContentProcessTerminated?()
        if isShown?() == false {
            Pipeline.log.notice("web content process died in a background tab; restoring it when shown")
            unloadUntilShown()
            return
        }
        if !processState.shouldReloadAfterUnexpectedTermination() {
            Pipeline.log.error("web content process died twice; leaving the tab alone")
            return
        }
        Pipeline.log.notice("web content process died; reloading the tab")
        guard let url = URL(string: urlString), !urlString.isEmpty else { return }
        hasPresentedContent = false
        webView.load(URLRequest(url: url))
    }

    // MARK: - Page colour

    var holdsPageColor = false
    var isMeasuringBand = false
    var needsBandRemeasure = false

    // MARK: - Zoom

    private(set) var zoomChanges = 0

    func zoomDidChange() {
        zoomChanges &+= 1
        recordSiteZoom()
    }

    // MARK: - Per-site zoom

    private var zoomHost = ""

    fileprivate func applySiteZoom() {
        let host = SystemPages.isSystem(webView.url)
            ? ""
            : webView.url?.host()?.lowercased() ?? ""
        guard host != zoomHost else { return }
        zoomHost = host
        let remembered = host.isEmpty ? nil : context.pageZoom.level(for: host)
        webView.pageZoom = remembered ?? context.settings.pageZoom
        zoomChanges &+= 1
    }

    fileprivate func recordSiteZoom() {
        guard !isPrivate, !zoomHost.isEmpty else { return }
        context.pageZoom.set(webView.pageZoom, for: zoomHost, defaultZoom: context.settings.pageZoom)
    }

    // MARK: - Scroll return

    private(set) var lastReportedScrollY: Double = 0
    private var lastReportedScrollURL: URL?
    private var scrollReturns = ScrollReturnMemory()

    func rememberScrollOffset() {
        scrollReturns.remember(lastReportedScrollY, leaving: lastReportedScrollURL?.absoluteString)
    }

    func noteDocumentChanged() {
        lastReportedScrollY = 0
        lastReportedScrollURL = nil
        translation.documentChanged()
        if isShowingRealPage {
            find.pageChanged()
        }
    }

    func restoreScrollOffsetIfNeeded() {
        guard pendingTransition == .backForward,
              let stored = scrollReturns.offset(returningTo: webView.url?.absoluteString)
        else { return }
        lastReportedScrollY = stored
        lastReportedScrollURL = webView.url
        webView.evaluateJavaScript(Self.restoreScrollScript(to: stored), completionHandler: nil)
    }

    private(set) var pendingTransition: HistoryStore.Transition = .typed

    func noteTransition(_ transition: HistoryStore.Transition) {
        pendingTransition = transition
    }

    /// A new tab is still on its way to the start page; two navigations race.
    private func stopUncommittedStartPage() {
        guard committedURL == nil, SystemPages.isStart(webView.url) else { return }
        webView.stopLoading()
    }

    @discardableResult
    func load(_ url: URL, transition: HistoryStore.Transition = .typed) -> WKNavigation? {
        autofillSave.clear()
        pendingTransition = transition
        discardDeferredSession()
        stopUncommittedStartPage()
        permitSystemPage(url)
        // WebKit refuses a plain request for a file: URL and leaves the tab blank.
        if url.isFileURL {
            return webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            return webView.load(URLRequest(url: url))
        }
    }

    func loadHTML(_ html: String, baseURL: URL?) {
        autofillSave.clear()
        discardDeferredSession()
        stopUncommittedStartPage()
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    // MARK: - Deferred restore

    private(set) var isDeferred = false
    var reclaimState: TabReclaimState {
        processState.reclaimState
    }

    private var deferredState: Data?
    private var deferredURL: URL?

    func deferRestore(state: Data?, url: URL?) {
        guard state != nil || url != nil else { return }
        deferredState = state
        deferredURL = url
        isDeferred = true
    }

    private var cachedSessionState: Data?
    private var hasFreshSessionState = false

    private(set) var sessionStateGeneration = 1

    var sessionState: Data? {
        if isDeferred {
            return deferredState
        }
        guard isMaterialised else {
            return cachedSessionState
        }
        if !hasFreshSessionState {
            cachedSessionState = webView.interactionState as? Data
            hasFreshSessionState = true
        }
        return cachedSessionState
    }

    func invalidateSessionState() {
        hasFreshSessionState = false
        sessionStateGeneration &+= 1
    }

    func realizeDeferredSession() {
        guard isDeferred else { return }
        let state = deferredState
        let url = deferredURL
        processState.beginReload()
        clearDeferredSession()
        invalidateSessionState()
        isRestoring = true
        permitSystemPage(url)
        if let state {
            webView.interactionState = state
        } else if let url {
            webView.load(URLRequest(url: url))
        } else {
            isRestoring = false
        }
    }

    private func discardDeferredSession() {
        clearDeferredSession()
        processState.finishReload()
    }

    private func clearDeferredSession() {
        isDeferred = false
        deferredState = nil
        deferredURL = nil
    }

    func finishReclaim() {
        processState.finishReload()
    }

    func refreshCanvas(from webView: WKWebView) {
        canvasColor = isShowingRealPage && hasPresentedContent
            ? webView.underPageBackgroundColor
            : nil
    }

    private static let presentationUpdateSelector = Selector(("_doAfterNextPresentationUpdate:"))
    static let coverCeiling: Duration = .milliseconds(400)

    @ObservationIgnored var presentationClock: any Clock<Duration> = ContinuousClock()

    @ObservationIgnored private var coverHold: Task<Void, Never>?
    @ObservationIgnored private var isArmingPresentation = false

    func coverUntilPresented() {
        hasPresentedContent = false
        coverHold?.cancel()
        coverHold = nil
        awaitPresentation()
    }

    private func awaitPresentation() {
        guard webView.window != nil else { return }
        guard webView.responds(to: Self.presentationUpdateSelector) else {
            uncover()
            return
        }
        let done: @convention(block) () -> Void = { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.isArmingPresentation {
                    self.uncover()
                } else {
                    self.didPresentContent()
                }
            }
        }
        isArmingPresentation = true
        _ = webView.perform(Self.presentationUpdateSelector, with: done)
        isArmingPresentation = false
    }

    func didPresentContent() {
        guard !hasPresentedContent else { return }
        guard presentedFrameWouldFlash else {
            uncover()
            return
        }
        if coverHold == nil {
            coverHold = Task { [weak self, presentationClock] in
                try? await presentationClock.sleep(for: Self.coverCeiling)
                guard !Task.isCancelled else { return }
                self?.uncover()
            }
        }
        awaitPresentation()
    }

    private func uncover() {
        guard !hasPresentedContent else { return }
        coverHold?.cancel()
        coverHold = nil
        hasPresentedContent = true
        refreshCanvas(from: webView)
        refreshPageColor(from: webView)
    }

    private var presentedFrameWouldFlash: Bool {
        Self.wouldFlash(
            painting: webView.underPageBackgroundColor,
            inDark: webView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        )
    }
}

extension BrowserTab {
    func documentFilename(for url: URL?) -> String? {
        url.flatMap { documentTitles[Self.documentURL($0)] }
    }

    func noteMainFrameResponse(_ response: URLResponse) {
        guard let url = response.url.map(Self.documentURL) else { return }
        if response.mimeType?.lowercased() == "application/pdf",
           let filename = response.suggestedFilename, !filename.isEmpty {
            documentTitles[url] = filename
        } else {
            documentTitles[url] = nil
        }
    }

    private static func documentURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.fragment = nil
        return components.url ?? url
    }

    func refreshChrome() {
        isLoading = webView.isLoading && isShowingRealPage && !stoppedNavigation
        canGoBackInWeb = webView.canGoBack
        canGoForwardInWeb = webView.canGoForward
        let displaced = committedURL
        committedURL = webView.backForwardList.currentItem?.url
        let url = webView.url
        if let page = InternalPage(url: url) {
            urlString = url?.absoluteString ?? page.url.absoluteString
            title = page.title
            favicon = nil
        } else if SystemPages.isStart(url) {
            // Do not replace the title of a failed navigation still covering the start page.
            let leftOwnPage = InternalPage(url: URL(string: urlString)) != nil
            if urlString.isEmpty || leftOwnPage || (displaced != nil && displaced != committedURL) {
                urlString = ""
                title = SystemPages.startTitle
                favicon = nil
            }
        } else {
            if let url, url.absoluteString != "about:blank" {
                urlString = url.absoluteString
            }
            if let pageTitle = webView.title, !pageTitle.isEmpty {
                title = pageTitle
            } else if isShowingRealPage, extensionBaseURL == nil, !isRestoring {
                title = documentFilename(for: url) ?? Self.placeholderTitle
            }
        }
        refreshSecurity()
        refreshCanvas(from: webView)
    }

    fileprivate func refreshSecurity() {
        guard !isShowingError, let scheme = webView.url?.scheme else {
            security = .none
            return
        }
        switch scheme {
        case "https":
            if webView.isLoading {
                security = .pending
            } else {
                security = webView.hasOnlySecureContent ? .secure : .mixed
            }
        case "http":
            security = .insecure
        default:
            security = .none
        }
    }

    func declaredFaviconChanged() {
        guard extensionBaseURL == nil, !isPrivate, !isShowingSystemPage else { return }
        guard let host = webView.url?.host()?.lowercased() else { return }
        context.favicons.forget(host: host)
        refreshFavicon()
    }

    func refreshFavicon() {
        guard extensionBaseURL == nil, isMaterialised else { return }
        guard !isPrivate, !isShowingSystemPage else { return }
        guard let host = webView.url?.host()?.lowercased() else { return }
        if host != faviconHost {
            faviconHost = host
            favicon = nil
        }
        if let cached = context.favicons.cached(for: host) {
            favicon = cached
            guard context.favicons.isGuessedIcon(for: host) else { return }
        }
        let view = webView
        let favicons = context.favicons
        Task { [weak self, weak view] in
            guard let view else { return }
            let icon = await favicons.load(for: view)
            guard let self, let icon, liveView === view, view.url?.host()?.lowercased() == host else { return }
            favicon = icon
        }
    }
}
