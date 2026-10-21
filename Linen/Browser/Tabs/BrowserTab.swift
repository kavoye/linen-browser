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
    private var documentTitles = DocumentTitles()

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
    var developerTools = DeveloperTools()
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
        events.onLinkHovered?(url, modifiers, anchor)
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

    var hasPresentedContent: Bool {
        cover.hasPresentedContent
    }

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

    var spaceID: UUID?

    // MARK: - The pin

    var pinnedURL: URL?
    var pinnedTitle = ""

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
    let events = TabEvents()

    let extensionBaseURL: URL?
    let popups: TabPopupPolicy
    let externalApps: TabExternalAppPolicy

    let permissions: TabPermissionCenter
    let assistantAccess: TabAssistantAccessCenter
    let find = FindSession()
    let reader = ReaderSession()
    var isSidebarActive = false
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

    @ObservationIgnored private let binding = TabWebViewBinding()
    private let processState = TabProcessState()
    @ObservationIgnored private(set) var cover: TabPresentationCover!
    private var siteZoom = TabSiteZoom()
    private var scrollReturn = TabScrollReturn()
    private var session = TabSessionMemory()
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
        cover = TabPresentationCover(
            view: { [weak self] in self?.webView },
            onUncover: { [weak self] in
                guard let self else { return }
                refreshCanvas(from: webView)
                refreshPageColor()
            }
        )
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
        binding.bind(webView, to: self)
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

    func setAgentWorking(_ isWorking: Bool) {
        processState.setAgentWorking(isWorking)
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
        cover.reset()
        deferRestore(state: state, url: url)
        processState.markUnloaded()
    }

    private func retire(_ outgoing: WKWebView) {
        outgoing.stopLoading()
        binding.unbind(outgoing)
        outgoing.removeFromSuperview()
        binding.stopObserving()
        permissions.onRevoke = nil
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
        events.onContentProcessTerminated?()
        retire(outgoing)
        stoppedNavigation = false
        provisionalNavigation = nil
        committedNavigation = nil
        isRestoring = false
        isLoading = false
        progress = 0
        cover.reset()
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

    func pageDidChangeInPlace(_ webView: WKWebView) {
        let previous = urlString
        if !SystemPages.isStart(webView.url) {
            permissions.pageChanged(url: webView.url)
            assistantAccess.pageChanged(url: webView.url)
        }
        applySiteZoom()
        applySitePopups()
        refreshChrome()
        guard urlString != previous else { return }
        refreshPageColor()
        refreshFavicon()
        measureBandUnderBar()
        invalidateSessionState()
        readerPageMoved(from: previous)
        translationPageMoved()
        events.onSameDocumentNavigation?()
        if movedWithinDocument(from: previous) {
            events.onInPageMove?()
        }
    }

    private(set) var isClosed = false

    func detach() {
        guard !isClosed else { return }
        isClosed = true
        reader.close()
        events.removeAll()
        binding.release()
        if translation.isActive, let liveView {
            translation.showOriginal(in: liveView)
        }
        translation.documentChanged()
        guard let view = liveView else { return }
        binding.unbind(view)
    }

    func contentProcessDidTerminate() {
        guard !isClosed else { return }
        isPlayingAudio = false
        events.onContentProcessTerminated?()
        if events.isShown?() == false {
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
        cover.reset()
        webView.load(URLRequest(url: url))
    }

    // MARK: - Page colour

    var holdsPageColor = false
    var isMeasuringBand = false
    var needsBandRemeasure = false

    // MARK: - Zoom

    var zoomChanges: Int {
        siteZoom.changes
    }

    func zoomDidChange() {
        siteZoom.noteChange()
        siteZoom.record(from: webView, context: context, isPrivate: isPrivate)
    }

    private func applySiteZoom() {
        siteZoom.apply(to: webView, context: context)
    }

    // MARK: - Scroll return

    var lastReportedScrollY: Double {
        scrollReturn.lastY
    }

    func reportScrollPosition(_ y: Double, at url: URL?) {
        scrollReturn.report(y, at: url)
    }

    func rememberScrollOffset() {
        scrollReturn.remember()
    }

    func noteDocumentChanged() {
        scrollReturn.forget()
        translation.documentChanged()
        if isShowingRealPage {
            find.pageChanged()
        }
    }

    func restoreScrollOffsetIfNeeded() {
        guard pendingTransition == .backForward,
              let stored = scrollReturn.offset(returningTo: webView.url)
        else { return }
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

    var isDeferred: Bool {
        session.isDeferred
    }

    var reclaimState: TabReclaimState {
        processState.reclaimState
    }

    var sessionStateGeneration: Int {
        session.generation
    }

    var sessionState: Data? {
        session.state(isMaterialised: isMaterialised) { webView.interactionState as? Data }
    }

    func deferRestore(state: Data?, url: URL?) {
        session.deferRestore(state: state, url: url)
    }

    func invalidateSessionState() {
        session.invalidate()
    }

    func realizeDeferredSession() {
        guard let deferred = session.takeDeferred() else { return }
        processState.beginReload()
        invalidateSessionState()
        isRestoring = true
        permitSystemPage(deferred.url)
        if let state = deferred.state {
            webView.interactionState = state
        } else if let url = deferred.url {
            webView.load(URLRequest(url: url))
        } else {
            isRestoring = false
        }
    }

    private func discardDeferredSession() {
        session.clearDeferred()
        processState.finishReload()
    }

    func finishReclaim() {
        processState.finishReload()
    }

    // MARK: - First paint

    static let coverCeiling = TabPresentationCover.ceiling

    var presentationClock: any Clock<Duration> {
        get { cover.clock }
        set { cover.clock = newValue }
    }

    func refreshCanvas(from webView: WKWebView) {
        canvasColor = isShowingRealPage && hasPresentedContent
            ? webView.underPageBackgroundColor
            : nil
    }

    func coverUntilPresented() {
        cover.cover()
    }

    func didPresentContent() {
        cover.didPresent()
    }
}

extension BrowserTab {
    func documentFilename(for url: URL?) -> String? {
        documentTitles.filename(for: url)
    }

    func noteMainFrameResponse(_ response: URLResponse) {
        documentTitles.note(response)
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

    func refreshSecurity() {
        security = PageSecurity(of: webView, showingError: isShowingError)
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
