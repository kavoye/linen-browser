// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import WebKit

final class TabNavigationDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    weak var tab: BrowserTab?

    init(tab: BrowserTab) {
        self.tab = tab
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.shouldPerformDownload {
            downloadSource = navigationAction.request.url
            decisionHandler(.download)
            return
        }
        if let url = navigationAction.request.url, SystemPages.isSystem(url) {
            decisionHandler(Self.reaches(url, by: navigationAction, in: tab) ? .allow : .cancel)
            return
        }
        if let url = navigationAction.request.url, !ExternalApp.staysInWebView(url) {
            decisionHandler(.cancel)
            let window = webView.window
            Task { await ExternalApp.offerToOpen(url, in: window) }
            return
        }
        if let tab, let onOpenInNewTab = tab.onOpenInNewTab,
           navigationAction.navigationType == .linkActivated,
           navigationAction.modifierFlags.contains(.command)
               || navigationAction.buttonNumber == Self.middleButton,
           navigationAction.targetFrame?.isMainFrame != false,
           let url = navigationAction.request.url {
            decisionHandler(.cancel)
            onOpenInNewTab(url, navigationAction.modifierFlags.contains(.shift))
            return
        }
        if let tab, let onOpenInPeek = tab.onOpenInPeek,
           navigationAction.navigationType == .linkActivated,
           navigationAction.modifierFlags == .shift,
           navigationAction.targetFrame?.isMainFrame != false,
           let url = navigationAction.request.url {
            decisionHandler(.cancel)
            onOpenInPeek(url, Self.pointer(in: webView))
            return
        }
        if let tab, navigationAction.targetFrame?.isMainFrame != false {
            tab.rememberScrollOffset()
            if let mapped = Self.transition(for: navigationAction.navigationType) {
                tab.noteTransition(mapped)
            }
        }

        guard let tab, let base = tab.extensionBaseURL,
              let url = navigationAction.request.url,
              url.scheme != "about",
              url.scheme != base.scheme || url.host != base.host
        else {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        tab.onNavigationOutsideExtension?(url)
    }

    /// WebKit numbers the middle button 4, not NSEvent's 2.
    private static let middleButton = 4

    private static func reaches(
        _ url: URL,
        by action: WKNavigationAction,
        in tab: BrowserTab?
    ) -> Bool {
        guard let tab else { return false }
        if action.navigationType == .backForward || action.navigationType == .reload
            || tab.isRestoring {
            return true
        }
        return tab.permitsSystemPage(url)
    }

    private static func transition(
        for type: WKNavigationType
    ) -> HistoryStore.Transition? {
        switch type {
        case .linkActivated:
            .link
        case .formSubmitted, .formResubmitted:
            .formSubmit
        case .backForward:
            .backForward
        case .reload:
            .reload
        case .other:
            nil
        @unknown default:
            nil
        }
    }

    // MARK: - Second windows

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let tab, let onNewWindow = tab.onNewWindow else { return nil }

        let view = TabWebView(frame: webView.frame, configuration: configuration)
        BrowserSettings.shared.apply(to: view)
        view.allowsBackForwardNavigationGestures = true
        view.allowsMagnification = true

        let modifiers = navigationAction.modifierFlags
        let activate = !modifiers.contains(.command) || modifiers.contains(.shift)
        onNewWindow(view, activate)
        return view
    }

    func webViewDidClose(_ webView: WKWebView) {
        tab?.onCloseRequested?()
    }

    /// `WKUIDelegatePrivate`. WebKit tells the app itself, so these arrive even
    /// when the page cannot: spell them exactly or they never fire.
    @objc(_webView:mouseDidMoveOverElement:withFlags:userInfo:)
    func webView(
        _ webView: WKWebView,
        mouseDidMoveOverElement hitTestResult: NSObject?,
        withFlags flags: NSEvent.ModifierFlags,
        userInfo: Any?
    ) {
        var url: URL?
        if let hitTestResult,
           hitTestResult.responds(to: NSSelectorFromString("absoluteLinkURL")) {
            url = hitTestResult.value(forKey: "absoluteLinkURL") as? URL
        }
        tab?.noteHoveredLink(url, modifiers: flags, at: Self.pointer(in: webView))
    }

    private static func pointer(in webView: WKWebView) -> CGPoint {
        guard let window = webView.window else { return .zero }
        let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let inView = webView.convert(inWindow, from: nil)
        guard !webView.isFlipped else { return inView }
        return CGPoint(x: inView.x, y: webView.bounds.height - inView.y)
    }

    @objc(_webView:hasVideoInPictureInPictureDidChange:)
    func webView(_ webView: WKWebView, hasVideoInPictureInPictureDidChange isOut: Bool) {
        tab?.onPictureInPictureChanged?(isOut)
    }

    /// The floating window wants to hand the video back. WebKit will not finish
    /// that while the page has nowhere on screen to return to, and it asks here
    /// first, which is the only warning a window in the Dock ever gets.
    @objc(_webViewFullscreenMayReturnToInline:)
    func webViewFullscreenMayReturnToInline(_ webView: WKWebView) {
        tab?.onPictureReturnExpected?()
    }

    // MARK: - Page dialogs

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo
    ) async {
        await PageDialogs.alert(message, from: frame, in: webView.window)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo
    ) async -> Bool {
        await PageDialogs.confirm(message, from: frame, in: webView.window)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText:
            String?,
        initiatedByFrame frame: WKFrameInfo
    ) async -> String? {
        await PageDialogs.prompt(prompt, defaultText: defaultText, from: frame, in: webView.window)
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo
    ) async -> [URL]? {
        await PageDialogs.chooseFiles(parameters, in: webView.window)
    }

    // MARK: - The page's own print

    /// WebKit sends `window.print()` to this private selector. There is no
    /// public equivalent, so without it the call does nothing.
    @objc(_webView:printFrame:pdfFirstPageSize:completionHandler:)
    func webView(
        _ webView: WKWebView,
        printFrame frame: Any,
        pdfFirstPageSize: CGSize,
        completionHandler: @escaping () -> Void
    ) {
        PagePrinting.begin(for: webView, then: completionHandler)
    }

    // MARK: - Media capture

    func webView(
        _ webView: WKWebView,
        decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
        initiatedBy frame: WKFrameInfo,
        type: WKMediaCaptureType
    ) async -> WKPermissionDecision {
        guard let tab else { return .deny }
        let wanted: [WebPermission]
        switch type {
        case .camera:
            wanted = [.camera]
        case .microphone:
            wanted = [.microphone]
        case .cameraAndMicrophone:
            wanted = [.camera, .microphone]
        @unknown default:
            return .deny
        }
        for permission in wanted {
            guard await tab.permissions.decide(permission) else { return .deny }
        }
        return .grant
    }

    // MARK: - Downloads

    private var downloadSource: URL?

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        guard !navigationResponse.canShowMIMEType else {
            decisionHandler(.allow)
            return
        }
        downloadSource = navigationResponse.response.url
        decisionHandler(.download)
    }

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        hand(download, source: navigationAction.request.url)
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        hand(download, source: navigationResponse.response.url)
    }

    private func hand(_ download: WKDownload, source: URL?) {
        let origin = source ?? downloadSource
        downloadSource = nil
        tab?.onDownload?(download, origin)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if let tab, !isLoadingErrorPage {
            tab.isShowingError = false
        }
        tab?.provisionalNavigation = navigation
        tab?.refreshChrome()
        if let url = webView.url {
            tab?.onNavigationStarted?(url)
        }
    }

    // MARK: - Authentication

    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        switch AuthChallenge.decision(
            for: space,
            previousFailureCount: challenge.previousFailureCount
        ) {
        case .evaluateServerTrust:
            switch await CertificateTrust.decide(
                for: challenge,
                allowsExceptions: BrowserSettings.shared.allowsCertificateExceptions,
                in: webView.window
            ) {
            case .useDefaultHandling:
                return (.performDefaultHandling, nil)
            case .proceed(let credential):
                return (.useCredential, credential)
            case .cancel:
                return (.cancelAuthenticationChallenge, nil)
            }
        case .useDefaultHandling:
            return (.performDefaultHandling, nil)
        case .rejectProtectionSpace:
            return (.rejectProtectionSpace, nil)
        case .promptForCredential:
            let credential = await AuthChallenge.requestCredential(
                for: space,
                previousFailures: challenge.previousFailureCount,
                in: webView.window
            )
            guard let credential else { return (.cancelAuthenticationChallenge, nil) }
            return (.useCredential, credential)
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if tab?.provisionalNavigation === navigation {
            tab?.provisionalNavigation = nil
        }
        tab?.noteDocumentChanged()
        tab?.noteHoveredLink(nil)
        tab?.clearPageActivity()
        if let tab, tab.isShowingRealPage, !tab.hasPresentedContent {
            tab.coverUntilPresented()
        }
        tab?.holdPageColorUntilLoaded()
        tab?.refreshChrome()
        tab?.invalidateSessionState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let tab else { return }
        let wasRestore = tab.isRestoring
        tab.isRestoring = false
        tab.finishReclaim()
        isLoadingErrorPage = false
        tab.refreshChrome()
        tab.invalidateSessionState()
        guard tab.isShowingRealPage else {
            // Nothing to record, but the session still moved.
            tab.onNavigationFinished?(true)
            return
        }
        tab.didPresentContent()
        tab.refreshFavicon()
        tab.releasePageColorHold()
        tab.refreshPageColor(from: webView)
        tab.restoreScrollOffsetIfNeeded()
        tab.onNavigationFinished?(wasRestore || tab.isShowingError)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        tab?.isRestoring = false
        tab?.finishReclaim()
        tab?.releasePageColorHold()
        showError(error, in: webView)
        tab?.refreshChrome()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        if let tab, tab.provisionalNavigation === navigation {
            tab.provisionalNavigation = nil
            tab.releasePageColorHold()
            tab.refreshPageColor(from: webView)
        }
        tab?.isRestoring = false
        tab?.finishReclaim()
        showError(error, in: webView)
        tab?.refreshChrome()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        tab?.contentProcessDidTerminate()
    }

    private var isLoadingErrorPage = false

    private func showError(_ error: any Error, in webView: WKWebView) {
        guard let tab, !ErrorPage.isSilent(error) else { return }
        let fallback = URL(string: tab.urlString)
        guard ErrorPage.failedURL(from: error, fallback: fallback) != nil else { return }
        tab.isShowingError = true
        isLoadingErrorPage = true
        ErrorPage.show(error, in: webView, fallbackURL: fallback)
    }
}
