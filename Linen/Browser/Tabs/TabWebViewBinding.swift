// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import WebKit

@MainActor
final class TabWebViewBinding {
    private let observations = WebViewObservations()
    private var navigationDelegate: TabNavigationDelegate?

    func bind(_ webView: WKWebView, to tab: BrowserTab) {
        observations.watch(webView, \.fullscreenState) { [weak tab] view in
            BrowserTab.applyObscuredInsets(to: view, isUnderTopBar: tab?.isUnderTopBar ?? true)
        }
        let delegate = TabNavigationDelegate(tab: tab)
        navigationDelegate = delegate
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        if let tabView = webView as? TabWebView {
            connect(tabView, to: tab)
        }
        observe(webView, for: tab)
        tab.permissions.onRevoke = { [weak tab] permission in
            guard let tab else { return }
            switch permission {
            case .camera:
                tab.webView.setCameraCaptureState(.none)
            case .microphone:
                tab.webView.setMicrophoneCaptureState(.none)
            case .location:
                tab.events.onLocationRevoked?()
            case .notifications:
                break
            }
        }
    }

    func unbind(_ webView: WKWebView) {
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        navigationDelegate = nil
        guard let tabView = webView as? TabWebView else { return }
        tabView.onZoomChanged = nil
        tabView.onContextDownload = nil
        BrowserTab.disconnectLinkMenu(of: tabView)
        tabView.onPeekLink = nil
        tabView.onSummarizeLink = nil
        tabView.onPageActivity = nil
        tabView.onScrollPosition = nil
        tabView.onFaviconDeclarationChange = nil
        tabView.onPopupBlocked = nil
    }

    func release() {
        navigationDelegate = nil
    }

    func stopObserving() {
        observations.cancel()
    }

    private func connect(_ tabView: TabWebView, to tab: BrowserTab) {
        tabView.onContextDownload = { [weak tab] download, source in
            tab?.events.onDownload?(download, source)
        }
        tab.connectLinkMenu(of: tabView)
        tabView.onPeekLink = { [weak tab] url in
            guard let tab else { return }
            tab.events.onOpenInPeek?(url, TabNavigationDelegate.pointer(in: tab.webView))
        }
        tabView.onSummarizeLink = { [weak tab] url, anchor in
            guard let tab else { return }
            tab.events.onSummarizeLink?(url, anchor ?? TabNavigationDelegate.pointer(in: tab.webView))
        }
        tabView.onPageActivity = { [weak tab] signal in
            tab?.notePageActivity(signal)
        }
        PageActivityMonitor.shared.install(in: tabView)
        tabView.onScrollPosition = { [weak tab] y, url in
            tab?.reportScrollPosition(y, at: url)
        }
        ScrollPositionMonitor.shared.install(in: tabView)
        tabView.onFaviconDeclarationChange = { [weak tab] in
            tab?.declaredFaviconChanged()
        }
        FaviconWatcher.shared.install(in: tabView)
        PageClickWatcher.shared.install(in: tabView)
        tabView.onPopupBlocked = { [weak tab] url in
            tab?.popups.note(url)
        }
        let profileID = tab.context.profile.id
        SiteContentGuard.shared.install(in: tabView)
        PaymentCardAutofill.shared.install(in: tabView, profileID: profileID)
        ContactAutofill.shared.install(in: tabView, profileID: profileID)
        PasswordAutofill.shared.install(in: tabView, profileID: profileID)
        AutofillSaveCoordinator.shared.install(in: tabView, session: tab.autofillSave, profileID: profileID)
    }

    private func observe(_ webView: WKWebView, for tab: BrowserTab) {
        observations.watch(webView, \.estimatedProgress) { [weak tab] view in
            tab?.progress = view.estimatedProgress
        }
        observations.watch(webView, \.isLoading, initially: true) { [weak tab] _ in
            tab?.refreshChrome()
        }
        observations.watch(webView, \.url) { [weak tab] view in
            tab?.pageDidChangeInPlace(view)
        }
        observations.watch(webView, \.title) { [weak tab] _ in
            tab?.refreshChrome()
            tab?.events.onTitleChanged?()
        }
        observations.watch(webView, \.canGoBack) { [weak tab] _ in
            tab?.refreshChrome()
        }
        observations.watch(webView, \.canGoForward) { [weak tab] _ in
            tab?.refreshChrome()
        }
        observations.watch(webView, \.hasOnlySecureContent) { [weak tab] _ in
            tab?.refreshSecurity()
        }
        observations.watch(webView, \.underPageBackgroundColor, initially: true) { [weak tab] view in
            tab?.refreshCanvas(from: view)
            tab?.measureBandUnderBar()
        }
        observations.watch(webView, \.cameraCaptureState, initially: true) { [weak tab] view in
            tab?.permissions.setLive(.camera, view.cameraCaptureState != .none)
        }
        observations.watch(webView, \.microphoneCaptureState, initially: true) { [weak tab] view in
            tab?.permissions.setLive(.microphone, view.microphoneCaptureState != .none)
        }
    }
}
