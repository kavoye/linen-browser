// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct ExtensionPageAssetsTests {
    private static let handlerName = "probe"
    private let probeURL = URL(string: "https://example.com/")!

    private final class Collector: NSObject, WKScriptMessageHandler {
        var messages: [String] = []

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            messages.append(message.body as? String ?? "")
        }
    }

    @MainActor
    private final class ProbeWindow: NSObject, WKWebExtensionWindow, WKWebExtensionControllerDelegate {
        var tabs: [ProbeTab] = []

        func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
            tabs
        }

        func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
            tabs.last
        }

        func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType {
            .normal
        }

        func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState {
            .normal
        }

        func isPrivate(for context: WKWebExtensionContext) -> Bool {
            false
        }

        func frame(for context: WKWebExtensionContext) -> CGRect {
            CGRect(x: 0, y: 0, width: 800, height: 600)
        }

        func screenFrame(for context: WKWebExtensionContext) -> CGRect {
            CGRect(x: 0, y: 0, width: 1600, height: 1200)
        }

        func webExtensionController(
            _ controller: WKWebExtensionController,
            openWindowsFor extensionContext: WKWebExtensionContext
        ) -> [any WKWebExtensionWindow] {
            [self]
        }

        func webExtensionController(
            _ controller: WKWebExtensionController,
            focusedWindowFor extensionContext: WKWebExtensionContext
        ) -> (any WKWebExtensionWindow)? {
            self
        }
    }

    @MainActor
    private final class ProbeTab: NSObject, WKWebExtensionTab {
        let webView: WKWebView
        unowned let owner: ProbeWindow

        init(webView: WKWebView, owner: ProbeWindow) {
            self.webView = webView
            self.owner = owner
        }

        func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
            owner
        }

        func indexInWindow(for context: WKWebExtensionContext) -> Int {
            owner.tabs.firstIndex { $0 === self } ?? NSNotFound
        }

        func webView(for context: WKWebExtensionContext) -> WKWebView? {
            webView
        }

        func isSelected(for context: WKWebExtensionContext) -> Bool {
            owner.tabs.last === self
        }
    }

    private struct Harness {
        let controller: WKWebExtensionController
        let window: ProbeWindow
        let id: String
    }

    enum ConnectListener: String {
        case onConnect
        case onConnectExternal
        case both
    }

    private func probePackage(
        connectable: Bool = false,
        listens: ConnectListener = .onConnect
    ) throws -> URL {
        let package = FileManager.default.temporaryDirectory
            .appendingPathComponent("linen-page-assets-\(UUID().uuidString)", isDirectory: true)
        let web = package.appendingPathComponent("web", isDirectory: true)
        try FileManager.default.createDirectory(at: web, withIntermediateDirectories: true)
        var manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Page Assets Probe",
            "description": "Reports what a page sees of an injected extension script.",
            "version": "1.0",
            "content_scripts": [
                [
                    "matches": ["<all_urls>"],
                    "js": ["content.js"],
                    "run_at": "document_start",
                ],
            ],
            "web_accessible_resources": [
                [
                    "resources": ["web/*"],
                    "matches": ["<all_urls>"],
                ],
            ],
        ]
        if connectable {
            manifest["externally_connectable"] = ["matches": ["<all_urls>"]]
            manifest["background"] = ["scripts": ["worker.js"], "service_worker": "worker.js"]
            manifest["content_scripts"] = [
                [
                    "matches": ["<all_urls>"],
                    "js": ["content.js"],
                    "run_at": "document_idle",
                ],
            ]
            let events: [String]
            switch listens {
            case .onConnect:
                events = ["onConnect"]
            case .onConnectExternal:
                events = ["onConnectExternal"]
            case .both:
                events = ["onConnect", "onConnectExternal"]
            }
            let registrations = events
                .map { "api.runtime.\($0).addListener(accept);" }
                .joined(separator: "\n            ")
            try """
            const api = globalThis.browser ?? globalThis.chrome;
            function accept(port) {
              port.onMessage.addListener((message) => {
                if (message && message.type === "ping") {
                  port.postMessage({ type: "pong", name: port.name, n: message.n });
                }
              });
            }
            \(registrations)
            """.write(to: package.appendingPathComponent("worker.js"), atomically: true, encoding: .utf8)
        }
        try JSONSerialization.data(withJSONObject: manifest)
            .write(to: package.appendingPathComponent("manifest.json"))
        let probeFile = connectable ? "connect.js" : "probe.js"
        try """
        const base = (globalThis.browser ?? globalThis.chrome).runtime.getURL("web");
        const script = document.createElement("script");
        script.src = base + "/\(probeFile)";
        script.dataset.path = base;
        document.documentElement.dataset.probeContent = "ran";
        (document.head || document.documentElement).appendChild(script);
        """.write(to: package.appendingPathComponent("content.js"), atomically: true, encoding: .utf8)
        try """
        (() => {
          const post = (text) => window.webkit.messageHandlers.\(Self.handlerName).postMessage(text);
          const current = document.currentScript;
          post("src:" + (current ? current.src : "<no currentScript>"));
          post("attr:" + (current ? current.getAttribute("src") : "<no currentScript>"));
          post("path:" + (current ? current.dataset.path : "<no currentScript>"));
          const base = current ? current.src.replace(/\\/[^\\/]+$/, "") : "";
          const link = document.createElement("link");
          link.rel = "stylesheet";
          link.href = base + "/probe.css";
          link.onload = () => post("css:loaded");
          link.onerror = () => post("css:error");
          document.head.appendChild(link);
          fetch(base + "/probe.txt")
            .then((response) => response.text())
            .then((text) => post("fetch:" + text.trim()))
            .catch((error) => post("fetch:error " + error.message));
          const chunk = document.createElement("script");
          chunk.src = base + "/chunk.js";
          chunk.onerror = () => post("script:error");
          document.head.appendChild(chunk);
        })();
        """.write(to: web.appendingPathComponent("probe.js"), atomically: true, encoding: .utf8)
        try """
        (() => {
          const post = (text) => window.webkit.messageHandlers.\(Self.handlerName).postMessage(text);
          const ids = (document.documentElement.dataset.linenExternalConnectable || "").split(",").filter(Boolean);
          post("ids:" + ids.length);
          if (!window.chrome || !window.chrome.runtime || !window.chrome.runtime.connect) {
            post("connect:missing");
            return;
          }
          const port = window.chrome.runtime.connect(ids[0] || "nobody", { name: "probe-port" });
          port.onMessage.addListener((message) => post("port:" + JSON.stringify(message)));
          port.onDisconnect.addListener(() => post("disconnected:" + (window.chrome.runtime.lastError ? window.chrome.runtime.lastError.message : "")));
          port.postMessage({ type: "ping", n: 7 });
        })();
        """.write(to: web.appendingPathComponent("connect.js"), atomically: true, encoding: .utf8)
        try "body { --probe: 1; }".write(to: web.appendingPathComponent("probe.css"), atomically: true, encoding: .utf8)
        try "ok".write(to: web.appendingPathComponent("probe.txt"), atomically: true, encoding: .utf8)
        try "window.webkit.messageHandlers.\(Self.handlerName).postMessage('script:ran');"
            .write(to: web.appendingPathComponent("chunk.js"), atomically: true, encoding: .utf8)
        return package
    }

    private func loadedHarness(for package: URL) async throws -> Harness {
        let controller = WKWebExtensionController(configuration: .nonPersistent())
        let window = ProbeWindow()
        controller.delegate = window
        controller.didOpenWindow(window)
        controller.didFocusWindow(window)
        ExtensionShims.ensureApplied(at: package)
        ExtensionExternalConnect.ensureRelayApplied(at: package)
        ExtensionPageAssets.ensureReporterApplied(at: package)
        let webExtension = try await WKWebExtension(resourceBaseURL: package)
        let context = WKWebExtensionContext(for: webExtension)
        let id = "probe" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        context.uniqueIdentifier = id
        if let base = URL(string: "webkit-extension://\(id)/") {
            context.baseURL = base
        }
        for permission in webExtension.requestedPermissions {
            context.setPermissionStatus(.grantedExplicitly, for: permission)
        }
        for pattern in webExtension.allRequestedMatchPatterns {
            context.setPermissionStatus(.grantedExplicitly, for: pattern)
        }
        try controller.load(context)
        return Harness(controller: controller, window: window, id: id)
    }

    private func page(
        _ harness: Harness,
        pageWorldScripts: [String] = [],
        url: URL
    ) -> (WKWebView, Collector, NSWindow) {
        let controller = harness.controller
        let collector = Collector()
        // Content scripts inject only into a view built from the controller's
        // own configuration, which every page here shares.
        let configuration = controller.configuration.webViewConfiguration
            ?? WebViewPool.makeConfiguration()
        configuration.webExtensionController = controller
        configuration.userContentController.removeAllUserScripts()
        configuration.userContentController.removeScriptMessageHandler(forName: Self.handlerName)
        configuration.userContentController.add(collector, name: Self.handlerName)
        for source in pageWorldScripts {
            configuration.userContentController.addUserScript(WKUserScript(
                source: source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ))
        }
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 800, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        window.orderBack(nil)
        let tab = ProbeTab(webView: webView, owner: harness.window)
        harness.window.tabs.append(tab)
        controller.didOpenTab(tab)
        controller.didActivateTab(tab, previousActiveTab: nil)
        webView.load(URLRequest(url: url))
        return (webView, collector, window)
    }

    private func waitForMessages(_ collector: Collector, count: Int, limit: Duration = .seconds(6)) async {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline, collector.messages.count < count {
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    private func value(_ prefix: String, in collector: Collector) -> String? {
        collector.messages.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }

    @Test func whatThePageSeesOfAnInjectedExtensionScript() async throws {
        let package = try probePackage()
        defer { try? FileManager.default.removeItem(at: package) }
        let harness = try await loadedHarness(for: package)
        let (webView, collector, window) = page(
            harness, url: probeURL
        )
        await waitForMessages(collector, count: 6, limit: .seconds(8))
        window.orderOut(nil)
        _ = webView

        #expect(value("src:", in: collector) == "webkit-masked-url://hidden/")
        #expect(value("attr:", in: collector) == "webkit-masked-url://hidden/")
        #expect(value("path:", in: collector) == "webkit-extension://\(harness.id)/web")
        #expect(value("css:", in: collector) == "error")
    }

    @Test func aPatchedCurrentScriptHandsBackTheRealBase() async throws {
        let package = try probePackage()
        defer { try? FileManager.default.removeItem(at: package) }
        let harness = try await loadedHarness(for: package)
        let (webView, collector, window) = page(
            harness,
            pageWorldScripts: [ExtensionPageAssets.script],
            url: probeURL
        )
        await waitForMessages(collector, count: 6, limit: .seconds(8))
        window.orderOut(nil)
        _ = webView

        let src = try #require(value("src:", in: collector))
        #expect(src.hasPrefix("webkit-extension://\(harness.id)/web/"), "\(src)")
        #expect(value("css:", in: collector) == "loaded")
        #expect(value("fetch:", in: collector) == "ok")
        #expect(value("script:", in: collector) == "ran", "\(collector.messages)")
    }

    @Test func aPageCanReachAConnectableExtensionsWorker() async throws {
        let package = try probePackage(connectable: true)
        defer { try? FileManager.default.removeItem(at: package) }
        let harness = try await loadedHarness(for: package)
        let (webView, collector, window) = page(
            harness,
            pageWorldScripts: [ExtensionPageAssets.script, ExtensionExternalConnect.pageScript],
            url: probeURL
        )
        await waitForMessages(collector, count: 2, limit: .seconds(30))
        window.orderOut(nil)
        _ = webView

        #expect(value("ids:", in: collector) == "1", "\(collector.messages)")
        #expect(value("port:", in: collector) == #"{"type":"pong","name":"probe-port","n":7}"#, "\(collector.messages)")
    }

    /// WebKit idles a non-persistent worker. A page opened long after the last
    /// one must still reach it, or an extension that keeps its settings there
    /// comes up with none of them.
    @Test(.timeLimit(.minutes(3))) func anIdledWorkerStillAnswersAFreshPort() async throws {
        let package = try probePackage(connectable: true)
        defer { try? FileManager.default.removeItem(at: package) }
        let harness = try await loadedHarness(for: package)
        let scripts = [ExtensionPageAssets.script, ExtensionExternalConnect.pageScript]

        let first = page(
            harness,
            pageWorldScripts: scripts,
            url: probeURL
        )
        await waitForMessages(first.1, count: 2, limit: .seconds(30))
        first.2.orderOut(nil)
        first.0.loadHTMLString("<html></html>", baseURL: nil)
        #expect(first.1.messages.contains { $0.hasPrefix("port:") }, "\(first.1.messages)")

        try await Task.sleep(for: .seconds(75))

        let second = page(
            harness,
            pageWorldScripts: scripts,
            url: probeURL
        )
        await waitForMessages(second.1, count: 2, limit: .seconds(30))
        second.2.orderOut(nil)
        _ = second.0

        #expect(second.1.messages.contains { $0.hasPrefix("port:") }, "\(second.1.messages)")
        #expect(!second.1.messages.contains { $0.hasPrefix("disconnected:") }, "\(second.1.messages)")
    }

    /// Chrome delivers a page's connection as onConnectExternal. A worker that
    /// listens on either event must hear it, and one listening on both must
    /// hear it once — FFZ registers both, and a doubled port answers twice.
    @Test(arguments: [ConnectListener.onConnect, .onConnectExternal, .both])
    func aPageReachesAWorkerWhicheverConnectEventItListensOn(
        listens: ConnectListener
    ) async throws {
        let package = try probePackage(connectable: true, listens: listens)
        defer { try? FileManager.default.removeItem(at: package) }
        let harness = try await loadedHarness(for: package)
        let (webView, collector, window) = page(
            harness,
            pageWorldScripts: [ExtensionPageAssets.script, ExtensionExternalConnect.pageScript],
            url: probeURL
        )
        await waitForMessages(collector, count: 2, limit: .seconds(30))
        try? await Task.sleep(for: .seconds(1))
        window.orderOut(nil)
        _ = webView

        let pongs = collector.messages.filter { $0.hasPrefix("port:") }
        #expect(pongs.count == 1, "\(listens.rawValue): \(collector.messages)")
        #expect(pongs.first?.contains(#""name":"probe-port""#) == true, "\(collector.messages)")
    }
}
