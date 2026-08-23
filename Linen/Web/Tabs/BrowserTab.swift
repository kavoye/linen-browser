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
    case mixed
    case insecure
    case none
}

@MainActor
@Observable
final class BrowserTab: Identifiable {
    static let placeholderTitle = String(localized: "New Tab")

    let id: UUID
    var title = BrowserTab.placeholderTitle
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

    private var webCanGoBack = false
    private var webCanGoForward = false

    private let beganOnStartPage: Bool

    var isShowingStartPage = false {
        didSet {
            guard isShowingStartPage != oldValue else { return }
            if isShowingStartPage {
                coveredTitle = title
                coveredFavicon = favicon
                title = Self.placeholderTitle
                favicon = nil
            } else {
                if let coveredTitle {
                    title = coveredTitle
                }
                favicon = coveredFavicon
                forgetCoveredPage()
            }
        }
    }

    private var coveredTitle: String?
    private var coveredFavicon: NSImage?

    private func forgetCoveredPage() {
        coveredTitle = nil
        coveredFavicon = nil
    }

    var canReturnToStartPage: Bool {
        beganOnStartPage
            && !isShowingStartPage
            && !webCanGoBack
            && !hasNoPageYet
            && internalPage == nil
    }

    var canGoBack: Bool {
        webCanGoBack || canReturnToStartPage
    }

    private var historyFloor = 0

    enum StartPageHistory {
        static func floor(backCount: Int, hasCurrentItem: Bool) -> Int {
            backCount + (hasCurrentItem ? 1 : 0)
        }

        static func reachable<Item>(_ list: [Item], floor: Int) -> [Item] {
            guard floor > 0, floor <= list.count else { return list }
            return Array(list.dropFirst(floor))
        }
    }

    var reachableBackList: [WKBackForwardListItem] {
        StartPageHistory.reachable(webView.backForwardList.backList, floor: historyFloor)
    }
    var canGoForward: Bool {
        webCanGoForward || isShowingStartPage
    }

    func goBack() {
        if webCanGoBack {
            webView.goBack()
            return
        }
        guard canReturnToStartPage else { return }
        isShowingStartPage = true
    }

    func goForward() {
        if isShowingStartPage {
            isShowingStartPage = false
            return
        }
        webView.goForward()
    }

    var isUnderTopBar = false {
        didSet {
            guard isUnderTopBar != oldValue else { return }
            Self.applyObscuredInsets(to: webView, isUnderTopBar: isUnderTopBar)
            measureBandUnderBar()
        }
    }

    var isControlledByMediaDock = false

    private(set) var preview: NSImage?

    func refreshPreview() {
        guard isShowingRealPage, !isDeferred, webView.window != nil else { return }
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = 480
        configuration.afterScreenUpdates = false
        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            guard let image else { return }
            self?.preview = image
        }
    }

    private(set) var canvasColor: NSColor?

    private(set) var hasPresentedContent = false

    private(set) var security: PageSecurity = .none

    enum InternalPage: String, Codable, CaseIterable {
        case history
        case downloads
        case releaseNotes

        var title: String {
            switch self {
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
            case .history:
                "clock"
            case .downloads:
                "arrow.down"
            case .releaseNotes:
                "doc.text"
            }
        }
    }

    var internalPage: InternalPage?

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
    private(set) var webView: WKWebView
    var onNavigationFinished: ((Bool) -> Void)?
    var onNavigationOutsideExtension: ((URL) -> Void)?
    var onNewWindow: ((WKWebView, Bool) -> Void)?
    var onOpenInNewTab: ((URL, Bool) -> Void)?
    var onOpenInSplit: ((URL) -> Void)?
    var onCloseRequested: (() -> Void)?
    var onPictureInPictureChanged: ((Bool) -> Void)?
    var onPictureReturnExpected: (() -> Void)?
    var onDownload: ((WKDownload, URL?) -> Void)?

    let extensionBaseURL: URL?

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
        permissions = TabPermissionCenter(store: sitePermissions)
        assistantAccess = TabAssistantAccessCenter(store: sitePermissions)
        permissions.persistsAnswers = !privately
        assistantAccess.persistsAnswers = !privately
        beganOnStartPage = opensBlank && adopting == nil && extensionHost == nil && !restoring
        if let adopting {
            // WebKit requires this exact view, with the opener's configuration attached.
            webView = adopting
            extensionBaseURL = nil
        } else if let extensionHost {
            webView = WebViewPool.shared.makeView(configuration: extensionHost.configuration)
            extensionBaseURL = extensionHost.baseURL
            title = extensionHost.name
            favicon = extensionHost.icon
        } else {
            webView = restoring
                ? WebViewPool.shared.makeColdView()
                : WebViewPool.shared.acquire()
            extensionBaseURL = nil
        }
        adopt(webView)
        find.driver = .webKit { [weak self] in self?.webView }
    }

    private func adopt(_ view: WKWebView) {
        webView = view
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
        permissions.pageChanged(url: webView.url)
        assistantAccess.pageChanged(url: webView.url)
        applySiteZoom()
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

    func contentProcessDidTerminate() {
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

    func refreshPageColor(from webView: WKWebView) {
        guard isShowingRealPage else {
            clearPageColor()
            return
        }
        guard provisionalNavigation == nil else { return }
        guard hasPresentedContent else {
            setPageColor(nil)
            return
        }
        measureBandUnderBar()
    }

    private var isMeasuringBand = false
    private var needsBandRemeasure = false

    func measureBandUnderBar() {
        guard isShowingRealPage, hasPresentedContent, webView.window != nil,
              webView.bounds.height > 0 else { return }
        guard !isMeasuringBand else {
            // The first presentation can still contain the old/blank frame.
            // Keep the didFinish request instead of dropping it behind that
            // early snapshot.
            needsBandRemeasure = true
            return
        }
        isMeasuringBand = true
        needsBandRemeasure = false
        let requestedURL = urlString
        let bandFraction = Theme.topBarHeight / webView.bounds.height
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = 48
        configuration.afterScreenUpdates = true
        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            guard let self else { return }
            isMeasuringBand = false
            let shouldRemeasure = needsBandRemeasure
            needsBandRemeasure = false
            defer {
                if shouldRemeasure {
                    measureBandUnderBar()
                }
            }
            guard urlString == requestedURL, provisionalNavigation == nil,
                  hasPresentedContent,
                  let image,
                  let average = Self.averageOfTopBand(of: image, fraction: bandFraction)
            else { return }
            setPageColor(average)
        }
    }

    func webViewDidBecomeVisible() {
        refreshCanvas(from: webView)
        refreshPageColor(from: webView)
    }

    static func averageOfTopBand(of image: NSImage, fraction: CGFloat) -> NSColor? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cg.height > 0
        else { return nil }
        let bandHeight = max(1, Int(CGFloat(cg.height) * min(max(fraction, 0), 1)))
        guard let band = cg.cropping(to: CGRect(x: 0, y: 0, width: cg.width, height: bandHeight)),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.interpolationQuality = .medium
        context.draw(band, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let data = context.data else { return nil }
        let pixel = data.bindMemory(to: UInt8.self, capacity: 4)
        return NSColor(
            srgbRed: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
    }

    fileprivate func clearPageColor() {
        setPageColor(nil)
    }

    private func setPageColor(_ color: NSColor?) {
        guard !Self.perceptuallyEqual(pageColor, color) else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            pageColor = color
        }
    }

    private static func perceptuallyEqual(_ a: NSColor?, _ b: NSColor?) -> Bool {
        guard let a = a?.usingColorSpace(.sRGB), let b = b?.usingColorSpace(.sRGB) else {
            return (a == nil) && (b == nil)
        }
        return abs(a.redComponent - b.redComponent) < 0.02
            && abs(a.greenComponent - b.greenComponent) < 0.02
            && abs(a.blueComponent - b.blueComponent) < 0.02
    }

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
        let host = webView.url?.host()?.lowercased() ?? ""
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

    func load(_ url: URL, transition: HistoryStore.Transition = .typed) {
        pendingTransition = transition
        discardDeferredSession()
        internalPage = nil
        if isShowingStartPage {
            let list = webView.backForwardList
            historyFloor = StartPageHistory.floor(
                backCount: list.backList.count,
                hasCurrentItem: list.currentItem != nil
            )
        }
        forgetCoveredPage()
        isShowingStartPage = false
        // WebKit refuses a plain request for a file: URL and leaves the tab blank.
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    func loadHTML(_ html: String, baseURL: URL?) {
        discardDeferredSession()
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

    fileprivate func refreshCanvas(from webView: WKWebView) {
        canvasColor = isShowingRealPage && hasPresentedContent
            ? webView.underPageBackgroundColor
            : nil
    }

    private static let presentationUpdateSelector = Selector(("_doAfterNextPresentationUpdate:"))

    func awaitFirstPresentation() {
        guard webView.window != nil else { return }
        guard webView.responds(to: Self.presentationUpdateSelector) else {
            didPresentContent()
            return
        }
        let done: @convention(block) () -> Void = { [weak self] in
            MainActor.assumeIsolated { self?.didPresentContent() }
        }
        _ = webView.perform(Self.presentationUpdateSelector, with: done)
    }

    func didPresentContent() {
        guard !hasPresentedContent else { return }
        hasPresentedContent = true
        refreshCanvas(from: webView)
        refreshPageColor(from: webView)
    }

    func refreshChrome() {
        isLoading = webView.isLoading && isShowingRealPage
        webCanGoBack = webView.canGoBack && !reachableBackList.isEmpty
        webCanGoForward = webView.canGoForward
        if let url = webView.url, url.absoluteString != "about:blank" {
            urlString = url.absoluteString
        }
        if let pageTitle = webView.title, !pageTitle.isEmpty {
            title = pageTitle
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
            security = webView.hasOnlySecureContent ? .secure : .mixed
        case "http":
            security = .insecure
        default:
            security = .none
        }
    }

    var isShowingError = false

    var isShowingRealPage: Bool {
        guard let scheme = webView.url?.scheme else { return false }
        return scheme != "about"
    }

    func declaredFaviconChanged() {
        guard extensionBaseURL == nil, !isPrivate else { return }
        guard let host = webView.url?.host()?.lowercased() else { return }
        FaviconLoader.shared.forget(host: host)
        refreshFavicon()
    }

    func refreshFavicon() {
        guard extensionBaseURL == nil else { return }
        guard !isPrivate else { return }
        guard let host = webView.url?.host()?.lowercased() else { return }
        if host != faviconHost {
            faviconHost = host
            favicon = nil
        }
        if let cached = FaviconLoader.shared.cached(for: host) {
            favicon = cached
            if !FaviconLoader.shared.isGuessedIcon(for: host) {
                return
            }
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
