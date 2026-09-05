// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Observation
import os
import SwiftUI
import WebKit

struct ExtensionPageHost {
    let configuration: WKWebViewConfiguration
    let baseURL: URL
    let name: String
    let icon: NSImage?
}

enum PageSecurity: Equatable {
    case secure
    case pending
    case mixed
    case insecure
    case none
}

@MainActor
@Observable
final class BrowserTab: Identifiable {
    static let placeholderTitle = String(localized: "New Tab")

    let id: UUID
    var pageTitle = BrowserTab.placeholderTitle
    var customTitle = ""

    var title: String {
        get { customTitle.isEmpty ? pageTitle : customTitle }
        set { pageTitle = newValue }
    }
    var urlString = ""
    var isLoading = false
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

    var backList: [WKBackForwardListItem] {
        guard isMaterialised else { return [] }
        return webView.backForwardList.backList
    }

    /// What WebKit has committed. `urlString` answers for a provisional
    /// navigation too, so the two disagree while a page is on its way in.
    private(set) var committedURL: URL?

    func goBack() {
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

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

    /// What the page itself is painted on: behind the web view before it has
    /// presented, and above it while a pull holds it down.
    var surfaceColor: Color {
        canvasColor.map(Color.init(nsColor:)) ?? Theme.windowBackground
    }

    private(set) var hasPresentedContent = false

    private(set) var security: PageSecurity = .none

    enum InternalPage: String, Codable, CaseIterable {
        case history
        case downloads
        case releaseNotes
        case settings

        var title: String {
            switch self {
            case .settings:
                "Settings"
            case .history:
                "History"
            case .downloads:
                "Downloads"
            case .releaseNotes:
                "Release Notes"
            }
        }

        var symbol: String {
            switch self {
            case .settings:
                "gearshape"
            case .history:
                "clock"
            case .downloads:
                "arrow.down"
            case .releaseNotes:
                "doc.text"
            }
        }
    }

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

    /// The one `linen:` address Linen asked for. Anything else asking is a
    /// website, and is refused.
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

    var isMaterialised: Bool {
        liveView != nil
    }

    var webView: WKWebView {
        if let liveView {
            return liveView
        }
        let view = WebViewPool.shared.makeColdView()
        liveView = view
        adopt(view)
        return view
    }
    var onNavigationStarted: ((URL) -> Void)?
    var onNavigationFinished: ((Bool) -> Void)?
    var onNavigationOutsideExtension: ((URL) -> Void)?
    var onNewWindow: ((WKWebView, Bool) -> Void)?
    var onOpenInNewTab: ((URL, Bool) -> Void)?
    var onOpenInPeek: ((URL, CGPoint) -> Void)?
    var onSummarizeLink: ((URL, CGPoint) -> Void)?
    var onCloseRequested: (() -> Void)?
    var onPictureInPictureChanged: ((Bool) -> Void)?
    var onPictureReturnExpected: (() -> Void)?
    var onDownload: ((WKDownload, URL?) -> Void)?
    var onLinkHovered: ((URL?, NSEvent.ModifierFlags, CGPoint) -> Void)?

    let extensionBaseURL: URL?
    let popups: TabPopupPolicy

    private var navigationDelegate: TabNavigationDelegate?
    let permissions: TabPermissionCenter
    let assistantAccess: TabAssistantAccessCenter
    let find = FindSession()

    let isPrivate: Bool

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

    init(
        id: UUID = UUID(),
        extensionHost: ExtensionPageHost? = nil,
        adopting: WKWebView? = nil,
        restoring: Bool = false,
        opensBlank: Bool = true,
        privately: Bool = false,
        sitePermissions: SitePermissions = .shared
    ) {
        self.id = id
        isPrivate = privately
        popups = TabPopupPolicy(store: sitePermissions)
        permissions = TabPermissionCenter(store: sitePermissions)
        assistantAccess = TabAssistantAccessCenter(store: sitePermissions)
        permissions.persistsAnswers = !privately
        assistantAccess.persistsAnswers = !privately
        let opensStartPage = opensBlank && adopting == nil && extensionHost == nil && !restoring
        if let adopting {
            // WebKit requires this exact view, with the opener's configuration attached.
            liveView = adopting
            extensionBaseURL = nil
        } else if let extensionHost {
            liveView = WebViewPool.shared.makeView(configuration: extensionHost.configuration)
            extensionBaseURL = extensionHost.baseURL
            pageTitle = extensionHost.name
            favicon = extensionHost.icon
        } else {
            liveView = restoring ? nil : WebViewPool.shared.acquire()
            extensionBaseURL = nil
        }
        if let liveView {
            adopt(liveView)
        }
        find.driver = .webKit { [weak self] in self?.webView }
        if opensStartPage, BrowserSettings.shared.newTab != .blank {
            permitSystemPage(SystemPages.start)
            webView.load(URLRequest(url: SystemPages.start))
        }
    }

    private func adopt(_ view: WKWebView) {
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
            tabView.onScrollPosition = { [weak self] y in
                self?.lastReportedScrollY = y
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

    func notePageActivity(_ signal: PageActivitySignal) {
        processState.notePageActivity(signal)
    }

    func clearPageActivity() {
        processState.clearPageActivity()
    }

    func discardWebContent() {
        guard canDiscardWebContent else { return }
        let state = sessionState
        let url = URL(string: urlString)
        guard state != nil || url != nil else { return }

        let outgoing = webView
        outgoing.stopLoading()
        outgoing.navigationDelegate = nil
        outgoing.uiDelegate = nil
        (outgoing as? TabWebView)?.onZoomChanged = nil
        (outgoing as? TabWebView)?.onContextDownload = nil
        (outgoing as? TabWebView)?.onPeekLink = nil
        (outgoing as? TabWebView)?.onSummarizeLink = nil
        (outgoing as? TabWebView)?.onPageActivity = nil
        (outgoing as? TabWebView)?.onFaviconDeclarationChange = nil
        outgoing.removeFromSuperview()

        adopt(WebViewPool.shared.makeColdView())
        hasPresentedContent = false
        deferRestore(state: state, url: url)
        processState.markUnloaded()
    }

    private static func applyObscuredInsets(
        to webView: WKWebView,
        isUnderTopBar: Bool = false
    ) {
        let isFullscreen = switch webView.fullscreenState {
        case .enteringFullscreen, .inFullscreen:
            true
        default:
            false
        }
        webView.obscuredContentInsets = NSEdgeInsets(
            top: isFullscreen || !isUnderTopBar ? 0 : Theme.topBarHeight,
            left: 0,
            bottom: 0,
            right: 0
        )
    }

    var onLocationRevoked: (() -> Void)?

    private func pageDidChangeInPlace(_ webView: WKWebView) {
        let previous = urlString
        // The start page is a surface over the tab, not a place it went.
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
        onSameDocumentNavigation?()
    }

    var onSameDocumentNavigation: (() -> Void)?

    var onContentProcessTerminated: (() -> Void)?

    private(set) var isClosed = false

    func detach() {
        guard !isClosed else { return }
        isClosed = true
        onNavigationStarted = nil
        onNavigationFinished = nil
        onNavigationOutsideExtension = nil
        onNewWindow = nil
        onOpenInNewTab = nil
        onOpenInPeek = nil
        onSummarizeLink = nil
        onCloseRequested = nil
        onPictureInPictureChanged = nil
        onPictureReturnExpected = nil
        onDownload = nil
        onLinkHovered = nil
        onSameDocumentNavigation = nil
        onContentProcessTerminated = nil
        onLocationRevoked = nil
        navigationDelegate = nil
        guard let view = liveView else { return }
        view.navigationDelegate = nil
        view.uiDelegate = nil
        (view as? TabWebView)?.onContextDownload = nil
        (view as? TabWebView)?.onPeekLink = nil
        (view as? TabWebView)?.onSummarizeLink = nil
        (view as? TabWebView)?.onZoomChanged = nil
    }

    func contentProcessDidTerminate() {
        guard !isClosed else { return }
        isPlayingAudio = false
        onContentProcessTerminated?()
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

    var zoomLevel: CGFloat {
        _ = zoomChanges
        return webView.pageZoom
    }

    var isZoomed: Bool {
        _ = zoomChanges
        return abs(webView.pageZoom - BrowserSettings.shared.pageZoom) > 0.005
            || abs(webView.magnification - 1) > 0.005
    }

    func zoomIn() {
        setPageZoom(webView.pageZoom + TabWebView.zoomStep)
    }

    func zoomOut() {
        setPageZoom(webView.pageZoom - TabWebView.zoomStep)
    }

    func resetZoom() {
        webView.magnification = 1
        webView.pageZoom = BrowserSettings.shared.pageZoom
        zoomDidChange()
    }

    private func setPageZoom(_ value: CGFloat) {
        webView.pageZoom = min(
            max(value, TabWebView.zoomRange.lowerBound),
            TabWebView.zoomRange.upperBound
        )
        zoomDidChange()
    }

    fileprivate func zoomDidChange() {
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
        let remembered = host.isEmpty ? nil : PageZoomStore.shared.level(for: host)
        webView.pageZoom = remembered ?? BrowserSettings.shared.pageZoom
        zoomChanges &+= 1
    }

    fileprivate func recordSiteZoom() {
        guard !isPrivate, !zoomHost.isEmpty else { return }
        PageZoomStore.shared.set(webView.pageZoom, for: zoomHost)
    }

    // MARK: - Scroll return

    private var lastReportedScrollY: Double = 0
    private var scrollReturns = ScrollReturnMemory()

    func rememberScrollOffset() {
        scrollReturns.remember(lastReportedScrollY, leaving: webView.url?.absoluteString)
    }

    func noteDocumentChanged() {
        lastReportedScrollY = 0
        if isShowingRealPage {
            find.pageChanged()
        }
    }

    func restoreScrollOffsetIfNeeded() {
        guard pendingTransition == .backForward,
              let stored = scrollReturns.offset(returningTo: webView.url?.absoluteString)
        else { return }
        lastReportedScrollY = stored
        webView.evaluateJavaScript(Self.restoreScrollScript(to: stored), completionHandler: nil)
    }

    private static func restoreScrollScript(to y: Double) -> String {
        """
        (() => {
          const target = \(y);
          if (window.scrollY > 1) return;
          let expected = window.scrollY;
          let tries = 20;
          const step = () => {
            if (Math.abs(window.scrollY - expected) > 1) return;
            window.scrollTo(0, target);
            expected = window.scrollY;
            if (Math.abs(expected - target) <= 1 || --tries <= 0) return;
            setTimeout(step, 60);
          };
          step();
        })();
        """
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

    func load(_ url: URL, transition: HistoryStore.Transition = .typed) {
        pendingTransition = transition
        discardDeferredSession()
        stopUncommittedStartPage()
        permitSystemPage(url)
        // WebKit refuses a plain request for a file: URL and leaves the tab blank.
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    func loadHTML(_ html: String, baseURL: URL?) {
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
    private static let coverCeiling: Duration = .milliseconds(400)

    @ObservationIgnored private var coverHold: Task<Void, Never>?

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
            MainActor.assumeIsolated { self?.didPresentContent() }
        }
        _ = webView.perform(Self.presentationUpdateSelector, with: done)
    }

    func didPresentContent() {
        guard !hasPresentedContent else { return }
        guard presentedFrameWouldFlash else {
            uncover()
            return
        }
        if coverHold == nil {
            coverHold = Task { [weak self] in
                try? await Task.sleep(for: Self.coverCeiling)
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

    static func wouldFlash(painting color: NSColor?, inDark: Bool) -> Bool {
        guard let painted = color?.usingColorSpace(.sRGB) else { return false }
        let luminance = 0.2126 * painted.redComponent
            + 0.7152 * painted.greenComponent
            + 0.0722 * painted.blueComponent
        return inDark ? luminance > 0.5 : luminance < 0.5
    }

    func refreshChrome() {
        isLoading = webView.isLoading && isShowingRealPage
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
            // The start page takes the row's name back only over a page that had one.
            let leftOwnPage = InternalPage(url: URL(string: urlString)) != nil
            if leftOwnPage || (displaced != nil && displaced != committedURL) {
                urlString = ""
                title = Self.placeholderTitle
                favicon = nil
            }
        } else {
            if let url, url.absoluteString != "about:blank" {
                urlString = url.absoluteString
            }
            if let pageTitle = webView.title, !pageTitle.isEmpty {
                title = pageTitle
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

    var isShowingError = false

    var isShowingRealPage: Bool {
        guard let scheme = webView.url?.scheme else { return false }
        return scheme != "about" && scheme != SystemPages.scheme
    }

    func declaredFaviconChanged() {
        guard extensionBaseURL == nil, !isPrivate, !isShowingSystemPage else { return }
        guard let host = webView.url?.host()?.lowercased() else { return }
        FaviconLoader.shared.forget(host: host)
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
        if let cached = FaviconLoader.shared.cached(for: host) {
            favicon = cached
            guard FaviconLoader.shared.isGuessedIcon(for: host) else { return }
        }
        Task { [weak self] in
            guard let self else { return }
            let icon = await FaviconLoader.shared.load(for: webView)
            guard let icon, webView.url?.host()?.lowercased() == host else { return }
            favicon = icon
        }
    }
}

extension BrowserTab: Equatable {
    nonisolated static func == (lhs: BrowserTab, rhs: BrowserTab) -> Bool {
        lhs === rhs
    }
}
