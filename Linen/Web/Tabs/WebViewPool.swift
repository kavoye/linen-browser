// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import WebKit

final class TabWebView: WKWebView {
    private static let newWindowItems: [String: LocalizedStringResource] = [
        "WKMenuItemIdentifierOpenLinkInNewWindow": "Open Link in New Tab",
        "WKMenuItemIdentifierOpenImageInNewWindow": "Open Image in New Tab",
        "WKMenuItemIdentifierOpenFrameInNewWindow": "Open Frame in New Tab",
        "WKMenuItemIdentifierOpenMediaInNewWindow": "Open Video in New Tab",
    ]

    static let liveInstances = NSHashTable<TabWebView>.weakObjects()

    static var refreshHoverShield: (() -> Void)?

    private(set) var isHoverParked = false
    private var parkedHoverAreas: [NSTrackingArea] = []

    func setHoverParked(_ parked: Bool) {
        guard parked != isHoverParked else { return }
        isHoverParked = parked
        if parked {
            for area in trackingAreas where area.owner !== self {
                parkedHoverAreas.append(area)
                super.removeTrackingArea(area)
            }
            NSCursor.arrow.set()
        } else {
            for area in parkedHoverAreas {
                super.addTrackingArea(area)
            }
            parkedHoverAreas.removeAll()
        }
    }

    override func addTrackingArea(_ trackingArea: NSTrackingArea) {
        if isHoverParked, trackingArea.owner !== self {
            parkedHoverAreas.append(trackingArea)
            return
        }
        super.addTrackingArea(trackingArea)
    }

    override func removeTrackingArea(_ trackingArea: NSTrackingArea) {
        parkedHoverAreas.removeAll { $0 === trackingArea }
        super.removeTrackingArea(trackingArea)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        Self.liveInstances.add(self)
        Self.refreshHoverShield?()
    }

    var onContextDownload: ((WKDownload, URL?) -> Void)?
    var onPageActivity: ((PageActivitySignal) -> Void)?
    var hasPageActivityMonitor = false
    var onScrollPosition: ((Double) -> Void)?
    var hasScrollPositionMonitor = false
    var onFaviconDeclarationChange: (() -> Void)?
    var hasFaviconWatcher = false
    var hasClickWatcher = false

    var onZoomChanged: (() -> Void)?

    // MARK: - Zoom

    static let zoomRange: ClosedRange<CGFloat> = 0.5...3
    static let zoomStep: CGFloat = 0.1

    private var wheelZoomBank: CGFloat = 0

    private static func isFromTouchSurface(_ event: NSEvent) -> Bool {
        !event.phase.isEmpty || !event.momentumPhase.isEmpty
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command), !Self.isFromTouchSurface(event) else {
            wheelZoomBank = 0
            super.scrollWheel(with: event)
            return
        }
        if event.hasPreciseScrollingDeltas {
            wheelZoomBank += event.scrollingDeltaY
            let threshold: CGFloat = 20
            while wheelZoomBank >= threshold {
                wheelZoomBank -= threshold
                stepZoom(Self.zoomStep)
            }
            while wheelZoomBank <= -threshold {
                wheelZoomBank += threshold
                stepZoom(-Self.zoomStep)
            }
        } else if event.scrollingDeltaY != 0 {
            stepZoom(event.scrollingDeltaY > 0 ? Self.zoomStep : -Self.zoomStep)
        }
    }

    override func magnify(with event: NSEvent) {
        super.magnify(with: event)
        guard event.phase == .ended || event.phase == .cancelled else { return }
        onZoomChanged?()
    }

    private func stepZoom(_ delta: CGFloat) {
        pageZoom = min(max(pageZoom + delta, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        onZoomChanged?()
    }

    private var contextImageURL: URL?
    private var contextLinkURL: URL?

    private static let reloadItem = "WKMenuItemIdentifierReload"

    private static let downloadItems: Set<String> = [
        "WKMenuItemIdentifierDownloadImage",
        "WKMenuItemIdentifierDownloadLinkedFile",
        "WKMenuItemIdentifierDownloadMedia",
    ]

    override func rightMouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let zoom = pageZoom == 0 ? 1 : pageZoom
        let x = local.x / zoom
        let y = (isFlipped ? local.y : bounds.height - local.y) / zoom

        contextImageURL = nil
        contextLinkURL = nil
        evaluateJavaScript(Self.hitTest(x: x, y: y)) { [weak self] value, _ in
            guard let self, let json = value as? String,
                  let data = json.data(using: .utf8),
                  let found = try? JSONSerialization.jsonObject(with: data) as? [String: String]
            else { return }
            contextImageURL = found["image"].flatMap(URL.init(string:))
            contextLinkURL = found["link"].flatMap(URL.init(string:))
        }

        super.rightMouseDown(with: event)
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        var reloadIndex: Int?
        for (index, item) in menu.items.enumerated() {
            guard let identifier = item.identifier?.rawValue else { continue }

            if let title = Self.newWindowItems[identifier] {
                item.title = String(localized: title)
            }

            if identifier == Self.reloadItem {
                item.title = String(localized: "Reload Page")
                reloadIndex = index
            }

            if Self.downloadItems.contains(identifier) {
                item.target = self
                item.action = #selector(startContextDownload(_:))
            }
        }

        guard let reloadIndex else { return }
        var index = reloadIndex + 1
        for item in pageItems() {
            menu.insertItem(item, at: index)
            index += 1
        }
    }

    private func pageItems() -> [NSMenuItem] {
        let save = NSMenuItem(
            title: String(localized: "Save Page As…"),
            action: #selector(savePage),
            keyEquivalent: ""
        )
        save.target = self
        save.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
        let printing = NSMenuItem(
            title: String(localized: "Print Page…"),
            action: #selector(printPage),
            keyEquivalent: ""
        )
        printing.target = self
        printing.image = NSImage(systemSymbolName: "printer", accessibilityDescription: nil)
        return [.separator(), save, printing]
    }

    @objc private func savePage() {
        PageSaving.begin(for: self)
    }

    @objc private func printPage() {
        PagePrinting.begin(for: self)
    }

    @objc private func startContextDownload(_ sender: NSMenuItem) {
        let isImage = sender.identifier?.rawValue == "WKMenuItemIdentifierDownloadImage"
        guard let url = isImage ? contextImageURL : (contextLinkURL ?? contextImageURL) else { return }
        startDownload(using: URLRequest(url: url)) { [weak self] download in
            self?.onContextDownload?(download, url)
        }
    }

    private static func hitTest(x: CGFloat, y: CGFloat) -> String {
        """
        (function () {
          var el = document.elementFromPoint(\(x), \(y));
          if (!el) { return ''; }
          var img = el.tagName === 'IMG' ? el : el.closest('img');
          var media = el.tagName === 'VIDEO' || el.tagName === 'AUDIO' ? el : el.closest('video, audio');
          var anchor = el.closest('a[href]');
          return JSON.stringify({
            image: img ? (img.currentSrc || img.src || '') : (media ? (media.currentSrc || media.src || '') : ''),
            link: anchor ? anchor.href : ''
          });
        })();
        """
    }
}

@MainActor
final class WebViewPool {
    static let shared = WebViewPool()

    nonisolated static let warmUpHTML = """
        <!doctype html><html><head>
        <meta name="color-scheme" content="light dark">
        <style>html { background: Canvas; }</style>
        </head><body></body></html>
        """

    nonisolated static let safariUserAgent = makeSafariUserAgent()

    nonisolated static var safariApplicationName: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "Version/\(os.majorVersion).\(os.minorVersion) Safari/605.1.15"
    }

    nonisolated static func makeSafariUserAgent(
        osVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> String {
        let version = "\(osVersion.majorVersion).\(osVersion.minorVersion)"
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) Version/\(version) Safari/605.1.15"
    }

    private var idle: [WKWebView] = []
    private let targetCount = 2
    private var refillTask: Task<Void, Never>?

    private struct PooledScript {
        let source: String
        let injectionTime: WKUserScriptInjectionTime
        let forMainFrameOnly: Bool
        let handlerName: String
        weak var handler: (any WKScriptMessageHandler & AnyObject)?
    }

    private var scripts: [PooledScript] = []

    private var extensionController: WKWebExtensionController?

    private(set) var dataStore: WKWebsiteDataStore = .default()

    func useDataStore(_ store: WKWebsiteDataStore) {
        guard store !== dataStore else { return }
        dataStore = store
        idle.removeAll()
    }

    func prepare(scriptSource: String, handlerName: String, handler: any WKScriptMessageHandler & AnyObject) {
        addScript(
            scriptSource,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false,
            handlerName: handlerName,
            handler: handler
        )
    }

    func addScript(
        _ source: String,
        injectionTime: WKUserScriptInjectionTime,
        forMainFrameOnly: Bool,
        handlerName: String,
        handler: any WKScriptMessageHandler & AnyObject
    ) {
        scripts.append(PooledScript(
            source: source,
            injectionTime: injectionTime,
            forMainFrameOnly: forMainFrameOnly,
            handlerName: handlerName,
            handler: handler
        ))
    }

    func installExtensionController(_ controller: WKWebExtensionController) {
        extensionController = controller
        idle.removeAll()
    }

    func warmUp() {
        while idle.count < targetCount {
            idle.append(makeWarmView())
        }
    }

    private func scheduleRefill() {
        guard refillTask == nil else { return }
        refillTask = Task { [weak self] in
            defer { self?.refillTask = nil }
            while self?.needsRefill == true {
                try? await Task.sleep(for: .milliseconds(320))
                guard !Task.isCancelled else { return }
                self?.appendWarmView()
            }
        }
    }

    private var needsRefill: Bool {
        idle.count < targetCount
    }

    private func appendWarmView() {
        guard needsRefill else { return }
        idle.append(makeWarmView())
    }

    func discardIdle() {
        idle.removeAll()
        scheduleRefill()
    }

    func makeView(configuration: WKWebViewConfiguration) -> WKWebView {
        let view = TabWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
        view.allowsBackForwardNavigationGestures = true
        view.allowsMagnification = true
        return view
    }

    func acquire() -> WKWebView {
        defer { scheduleRefill() }
        while let view = idle.popLast() {
            if view.configuration.websiteDataStore === dataStore {
                return view
            }
        }
        return makeWarmView()
    }

    func makeColdView() -> WKWebView {
        buildView()
    }

    static let warmsPooledViews = false

    private func makeWarmView() -> WKWebView {
        let view = buildView()
        guard Self.warmsPooledViews else { return view }
        view.loadHTMLString(Self.warmUpHTML, baseURL: nil)
        return view
    }

    private func buildView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.webExtensionController = extensionController
        BrowserSettings.shared.apply(to: configuration)
        MediaCenter.enablePictureInPicture(on: configuration.preferences)

        let contentController = WKUserContentController()
        for script in scripts {
            guard let handler = script.handler else { continue }
            contentController.addUserScript(WKUserScript(
                source: script.source,
                injectionTime: script.injectionTime,
                forMainFrameOnly: script.forMainFrameOnly
            ))
            contentController.add(handler, name: script.handlerName)
        }

        ContentBlocker.shared.apply(to: contentController)

        configuration.userContentController = contentController
        configuration.setURLSchemeHandler(SystemPageSchemeHandler(), forURLScheme: SystemPages.scheme)

        let view = TabWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
        BrowserSettings.shared.apply(to: view)
        view.allowsBackForwardNavigationGestures = true
        view.allowsMagnification = true
        return view
    }
}
