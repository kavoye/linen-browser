// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WebKit

struct WebViewRepresentable: NSViewRepresentable {
    let webView: WKWebView
    var parksWhenIdle = false

    func makeNSView(context: Context) -> WebViewContainer {
        let container = WebViewContainer(webView: webView)
        container.parksWhenIdle = parksWhenIdle
        return container
    }

    func updateNSView(_ nsView: WebViewContainer, context: Context) {
        nsView.parksWhenIdle = parksWhenIdle
        nsView.install(webView)
    }

    static func dismantleNSView(_ nsView: WebViewContainer, coordinator: ()) {
        nsView.uninstall()
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: WebViewContainer,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
}

@MainActor
enum WebKeyEcho {
    static func shouldSilenceUnhandledKey(from responder: NSResponder?) -> Bool {
        var view = responder as? NSView
        while let current = view {
            if current is WKWebView {
                return true
            }
            view = current.superview
        }
        return false
    }
}

@MainActor
enum WebViewParking {
    static func park(_ webView: WKWebView) {
        guard let shelf = webView.window?.contentView?.subviews
            .first(where: { $0 is WebViewParkingShelf })
        else {
            webView.removeFromSuperview()
            return
        }
        let size = webView.bounds.size
        webView.removeFromSuperview()
        webView.autoresizingMask = []
        webView.frame = NSRect(x: 0, y: 0, width: max(size.width, 1), height: max(size.height, 1))
        shelf.addSubview(webView)
    }
}

final class WebViewParkingShelf: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

final class WebViewContainer: NSView {
    var parksWhenIdle = false

    private weak var installedWebView: WKWebView?

    override var preservesContentDuringLiveResize: Bool {
        true
    }

    init(webView: WKWebView) {
        super.init(frame: .zero)
        install(webView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func install(_ webView: WKWebView) {
        if let installedWebView, installedWebView !== webView, installedWebView.superview === self {
            if parksWhenIdle {
                WebViewParking.park(installedWebView)
            } else {
                installedWebView.removeFromSuperview()
            }
        }
        installedWebView = webView
        attachIfHosted()
    }

    private func attachIfHosted() {
        guard window != nil, let webView = installedWebView, webView.superview !== self else { return }
        webView.removeFromSuperview()
        webView.autoresizingMask = [.width, .height]
        if bounds.width > 0, bounds.height > 0 {
            webView.frame = bounds
        }
        addSubview(webView)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachIfHosted()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard newWindow == nil, parksWhenIdle,
              let installedWebView, installedWebView.superview === self else { return }
        WebViewParking.park(installedWebView)
    }

    func uninstall() {
        guard let installedWebView else { return }
        if installedWebView.superview === self {
            if parksWhenIdle {
                WebViewParking.park(installedWebView)
            } else {
                installedWebView.removeFromSuperview()
            }
        }
        self.installedWebView = nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard installedWebView?.superview === self else { return }
        installedWebView?.frame = bounds
    }
}
