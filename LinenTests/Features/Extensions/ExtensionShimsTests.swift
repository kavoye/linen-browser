// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

struct ExtensionShimsTests {
    private func scratchPackage(manifest: [String: Any]) throws -> URL {
        let directory = TestFiles.directory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: manifest)
        try data.write(to: directory.appendingPathComponent("manifest.json"))
        return directory
    }

    private func scripts(at package: URL) throws -> [String] {
        let data = try Data(contentsOf: package.appendingPathComponent("manifest.json"))
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let background = root?["background"] as? [String: Any]
        return background?["scripts"] as? [String] ?? []
    }

    @Test func theShimBecomesTheFirstBackgroundScript() throws {
        let package = try scratchPackage(manifest: [
            "manifest_version": 2,
            "background": ["scripts": ["background/index.js"]],
        ])
        defer { try? FileManager.default.removeItem(at: package) }

        #expect(ExtensionShims.ensureApplied(at: package))
        #expect(try scripts(at: package) == [ExtensionShims.fileName, "background/index.js"])
        let shim = package.appendingPathComponent(ExtensionShims.fileName)
        #expect(FileManager.default.fileExists(atPath: shim.path))
    }

    @Test func applyingTwiceChangesNothing() throws {
        let package = try scratchPackage(manifest: [
            "manifest_version": 2,
            "background": ["scripts": ["bg.js"]],
        ])
        defer { try? FileManager.default.removeItem(at: package) }

        #expect(ExtensionShims.ensureApplied(at: package))
        let once = try Data(contentsOf: package.appendingPathComponent("manifest.json"))
        #expect(ExtensionShims.ensureApplied(at: package))
        let twice = try Data(contentsOf: package.appendingPathComponent("manifest.json"))
        #expect(once == twice)
        #expect(try scripts(at: package).count(where: { $0 == ExtensionShims.fileName }) == 1)
    }

    private func background(at package: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: package.appendingPathComponent("manifest.json"))
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return try #require(root?["background"] as? [String: Any])
    }

    private func text(_ path: String, in package: URL) throws -> String {
        try String(contentsOf: package.appendingPathComponent(path), encoding: .utf8)
    }

    @Test func aServiceWorkerRunsBehindAWrapperThatLoadsTheShimFirst() throws {
        let package = try scratchPackage(manifest: [
            "manifest_version": 3,
            "background": ["service_worker": "sw.js"],
        ])
        defer { try? FileManager.default.removeItem(at: package) }

        #expect(ExtensionShims.ensureApplied(at: package))
        let background = try background(at: package)
        #expect(background["service_worker"] as? String == ExtensionShims.workerFileName)
        #expect(background["scripts"] == nil)
        #expect(try text(ExtensionShims.workerFileName, in: package)
            == "importScripts(\"./\(ExtensionShims.fileName)\", \"./sw.js\");\n")
        let shim = package.appendingPathComponent(ExtensionShims.fileName)
        #expect(FileManager.default.fileExists(atPath: shim.path))
    }

    @Test func aNestedWorkerKeepsItsDirectory() throws {
        let package = try scratchPackage(manifest: [
            "manifest_version": 3,
            "background": ["service_worker": "./build/bg/sw.js"],
        ])
        defer { try? FileManager.default.removeItem(at: package) }
        try FileManager.default.createDirectory(
            at: package.appendingPathComponent("build/bg"), withIntermediateDirectories: true
        )

        #expect(ExtensionShims.ensureApplied(at: package))
        let wrapper = "build/bg/" + ExtensionShims.workerFileName
        #expect(try background(at: package)["service_worker"] as? String == wrapper)
        #expect(try text(wrapper, in: package)
            == "importScripts(\"../../\(ExtensionShims.fileName)\", \"./sw.js\");\n")
    }

    @Test func aModuleWorkerImportsTheShimFirst() throws {
        let package = try scratchPackage(manifest: [
            "manifest_version": 3,
            "background": ["service_worker": "sw.js", "type": "module"],
        ])
        defer { try? FileManager.default.removeItem(at: package) }

        #expect(ExtensionShims.ensureApplied(at: package))
        #expect(try text(ExtensionShims.workerFileName, in: package)
            == "import \"./\(ExtensionShims.fileName)\";\nimport \"./sw.js\";\n")
    }

    @Test func wrappingAWorkerTwiceChangesNothing() throws {
        let package = try scratchPackage(manifest: [
            "manifest_version": 3,
            "background": ["service_worker": "sw.js"],
        ])
        defer { try? FileManager.default.removeItem(at: package) }

        #expect(ExtensionShims.ensureApplied(at: package))
        let once = try Data(contentsOf: package.appendingPathComponent("manifest.json"))
        let wrapper = try text(ExtensionShims.workerFileName, in: package)
        #expect(ExtensionShims.ensureApplied(at: package))
        #expect(try Data(contentsOf: package.appendingPathComponent("manifest.json")) == once)
        #expect(try text(ExtensionShims.workerFileName, in: package) == wrapper)
    }

    @Test func aWorkerOutsideThePackageIsLeftAlone() throws {
        let package = try scratchPackage(manifest: [
            "manifest_version": 3,
            "background": ["service_worker": "../sw.js"],
        ])
        defer { try? FileManager.default.removeItem(at: package) }

        #expect(!ExtensionShims.ensureApplied(at: package))
        #expect(try background(at: package)["service_worker"] as? String == "../sw.js")
    }

    @Test func aPackageWithoutABackgroundIsLeftAlone() throws {
        let package = try scratchPackage(manifest: ["manifest_version": 2])
        defer { try? FileManager.default.removeItem(at: package) }

        #expect(!ExtensionShims.ensureApplied(at: package))
        let shim = package.appendingPathComponent(ExtensionShims.fileName)
        #expect(!FileManager.default.fileExists(atPath: shim.path))
    }

    @MainActor
    @Test(arguments: ["browser_action", "page_action", "action"])
    func emptyActionCommandsUseWebKitDefaults(action: String) async throws {
        let command = "_execute_" + action
        let package = try scratchPackage(manifest: [
            "manifest_version": action == "action" ? 3 : 2,
            "name": "Command test", "version": "1.0",
            "description": "Checks extension action commands.",
            action: ["default_title": "Open test"],
            "background": ["scripts": [ExtensionShims.fileName, "bg.js"], "persistent": false],
            "commands": [command: [:], "dashboard": ["description": "Open dashboard"]],
        ])
        defer { try? FileManager.default.removeItem(at: package) }
        try "".write(to: package.appendingPathComponent("bg.js"), atomically: true, encoding: .utf8)

        #expect(ExtensionShims.ensureApplied(at: package))
        let manifestURL = package.appendingPathComponent("manifest.json")
        let once = try Data(contentsOf: manifestURL)
        #expect(ExtensionShims.ensureApplied(at: package))
        #expect(try Data(contentsOf: manifestURL) == once)

        let webExtension = try await WKWebExtension(resourceBaseURL: package)
        let context = WKWebExtensionContext(for: webExtension)
        #expect(Set(context.commands.map(\.id)) == [command, "dashboard"])
        #expect(webExtension.errors.isEmpty, "\(webExtension.errors.map(\.localizedDescription))")
    }

    @Test func configuredShortcutsAndUnrelatedEmptyCommandsArePreserved() throws {
        let commands: [String: Any] = [
            "_execute_browser_action": ["suggested_key": ["default": "Ctrl+Shift+Y"]],
            "dashboard": ["description": "Open dashboard"],
            "unknown": [:],
            "_execute_page_action": [:],
        ]
        let package = try scratchPackage(manifest: [
            "manifest_version": 2, "browser_action": [:],
            "background": ["scripts": ["bg.js"]], "commands": commands,
        ])
        defer { try? FileManager.default.removeItem(at: package) }

        #expect(ExtensionShims.ensureApplied(at: package))
        let data = try Data(contentsOf: package.appendingPathComponent("manifest.json"))
        let manifest = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((manifest["commands"] as? NSDictionary) == commands as NSDictionary)
    }

    @Test func thePageScriptGoesFirstInTheHead() {
        let html = "<!DOCTYPE html><html><head>\n<title>T</title><script src=\"a.js\"></script></head><header></header></html>"
        let tag = "<script src=\"/\(ExtensionShims.pageFileName)\"></script>"
        #expect(ExtensionShims.inserting(script: ExtensionShims.pageFileName, into: html)
            == "<!DOCTYPE html><html><head>\(tag)\n<title>T</title><script src=\"a.js\"></script></head><header></header></html>")
        #expect(ExtensionShims.inserting(script: ExtensionShims.pageFileName, into: "<!doctype html><HEAD lang=en></HEAD>")
            == "<!doctype html><HEAD lang=en>\(tag)</HEAD>")
        #expect(ExtensionShims.inserting(script: ExtensionShims.pageFileName, into: "<!doctype html><script src=b.js></script>")
            == "<!doctype html>\(tag)<script src=b.js></script>")
        #expect(ExtensionShims.inserting(script: ExtensionShims.pageFileName, into: "<p>x</p>") == tag + "<p>x</p>")
        #expect(ExtensionShims.inserting(script: ExtensionShims.pageFileName, into: "<head>\(tag)</head>") == nil)
    }

    @Test func everyPageGetsThePageScriptAndABackgroundPageGetsTheBackgroundScript() throws {
        let package = try scratchPackage(manifest: [
            "manifest_version": 2,
            "background": ["page": "./bg/background.html"],
        ])
        defer { try? FileManager.default.removeItem(at: package) }
        try FileManager.default.createDirectory(
            at: package.appendingPathComponent("bg"), withIntermediateDirectories: true
        )
        for path in ["popup.html", "bg/background.html", "bg/options.htm"] {
            try "<html><head></head><body></body></html>"
                .write(to: package.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }

        #expect(ExtensionShims.ensurePagesApplied(at: package) == 3)
        #expect(try text("popup.html", in: package).contains("src=\"/\(ExtensionShims.pageFileName)\""))
        #expect(try text("bg/options.htm", in: package).contains("src=\"/\(ExtensionShims.pageFileName)\""))
        #expect(try text("bg/background.html", in: package).contains("src=\"/\(ExtensionShims.fileName)\""))
        #expect(try text(ExtensionShims.pageFileName, in: package) == ExtensionShims.pageSource)
        #expect(try text(ExtensionShims.fileName, in: package) == ExtensionShims.source)
        #expect(ExtensionShims.ensurePagesApplied(at: package) == 0)
    }

    @Test func aPackageWithoutPagesGetsNoPageScript() throws {
        let package = try scratchPackage(manifest: ["manifest_version": 3])
        defer { try? FileManager.default.removeItem(at: package) }

        #expect(ExtensionShims.ensurePagesApplied(at: package) == 0)
        let shim = package.appendingPathComponent(ExtensionShims.pageFileName)
        #expect(!FileManager.default.fileExists(atPath: shim.path))
    }
}

@MainActor
@Suite(.boundedWebViews)
struct ExtensionShimRuntimeTests {
    private func run(setup: String, body: String, shim: String = ExtensionShims.source) async throws -> [String: Any] {
        let configuration = WebViewPool.makeConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.loadHTMLString("<!doctype html><title>Shim test</title>", baseURL: nil)
        try #require(await PageSettle.untilIdle(view, timeout: .seconds(20)))
        let result = try await view.callAsyncJavaScript(
            setup + "\n" + shim + "\n" + body,
            arguments: [:], in: nil, contentWorld: .page
        )
        return try #require(result as? [String: Any])
    }

    @Test func missingEventsBecomeSilentAndPresentOnesAreKept() async throws {
        let result = try await run(setup: """
        const completed = { addListener() {} };
        const browser = { webNavigation: { onCompleted: completed } };
        """, body: """
        browser.webNavigation.onHistoryStateUpdated.addListener(() => {});
        browser.webNavigation.onTabReplaced.addListener(() => {});
        return {
            kept: browser.webNavigation.onCompleted === completed,
            listening: browser.webNavigation.onTabReplaced.hasListener(() => {}),
            tabs: "tabs" in browser
        };
        """)
        #expect(result["kept"] as? Bool == true)
        #expect(result["listening"] as? Bool == false)
        #expect(result["tabs"] as? Bool == false)
    }

    @Test func managedStorageIsEmptyAndReadOnly() async throws {
        let result = try await run(setup: """
        const browser = { storage: { local: {} } };
        """, body: """
        const managed = browser.storage.managed;
        const promised = await managed.get(null);
        const calledBack = await new Promise(resolve => managed.get("policy", resolve));
        let failure;
        try { await managed.set({ policy: 1 }); } catch (error) { failure = error.message; }
        return {
            promised: Object.keys(promised).length, calledBack: Object.keys(calledBack).length,
            bytes: await managed.getBytesInUse(null), failure,
            listening: managed.onChanged.hasListener(() => {})
        };
        """)
        #expect(result["promised"] as? Int == 0)
        #expect(result["calledBack"] as? Int == 0)
        #expect(result["bytes"] as? Int == 0)
        #expect(result["failure"] as? String == "storage.managed.set() isn't supported because managed storage is read-only.")
        #expect(result["listening"] as? Bool == false)
    }

    @Test func aRealManagedStorageIsKept() async throws {
        let result = try await run(setup: """
        const managed = { get: async () => ({ policy: 1 }) };
        const browser = { storage: { managed } };
        """, body: """
        return { kept: browser.storage.managed === managed };
        """)
        #expect(result["kept"] as? Bool == true)
    }

    @Test func aDeclaredAPIWebKitDropsFailsWithoutThrowing() async throws {
        let result = try await run(setup: """
        const tabs = { query: async () => [] };
        const browser = {
            tabs,
            runtime: { getManifest: () => ({ permissions: [
                "sidePanel", "system.cpu", "downloads", "tabs", "activeTab", "https://example.com/*"
            ] }) }
        };
        """, body: """
        let failure;
        try { await browser.sidePanel.setPanelBehavior({ openPanelOnActionClick: true }); }
        catch (error) { failure = error.message; }
        const calledBack = await new Promise(resolve => browser.sidePanel.open({}, value => resolve(value === undefined)));
        browser.sidePanel.onChanged.addListener(() => {});
        const awaited = await Promise.resolve(browser.sidePanel);
        return {
            failure, calledBack,
            silent: browser.sidePanel.onChanged.hasListener(() => {}) === false,
            awaited: awaited === browser.sidePanel,
            nested: typeof browser.system.cpu.getInfo,
            downloads: "downloads" in browser,
            activeTab: "activeTab" in browser,
            tabsKept: browser.tabs === tabs
        };
        """)
        #expect(result["failure"] as? String == "sidePanel.setPanelBehavior() isn't supported in Linen.")
        #expect(result["calledBack"] as? Bool == true)
        #expect(result["silent"] as? Bool == true)
        #expect(result["awaited"] as? Bool == true)
        #expect(result["nested"] as? String == "function")
        #expect(result["downloads"] as? Bool == false)
        #expect(result["activeTab"] as? Bool == false)
        #expect(result["tabsKept"] as? Bool == true)
    }

    @Test func anUndeclaredAPIStaysMissing() async throws {
        let result = try await run(setup: """
        const storage = { local: {}, managed: {} };
        const browser = { storage, runtime: { getManifest: () => ({ permissions: ["storage"] }) } };
        """, body: """
        return { sidePanel: "sidePanel" in browser, storageKept: browser.storage === storage };
        """)
        #expect(result["sidePanel"] as? Bool == false)
        #expect(result["storageKept"] as? Bool == true)
    }

    @Test func pagesKeepTheirOwnConnectListeners() async throws {
        let result = try await run(setup: """
        const onConnect = { addListener() {}, removeListener() {}, hasListener: () => false };
        const add = onConnect.addListener;
        const browser = { runtime: { onConnect, getManifest: () => ({ permissions: ["privacy"] }) } };
        """, body: """
        return { kept: browser.runtime.onConnect.addListener === add, privacy: "privacy" in browser };
        """, shim: ExtensionShims.pageSource)
        #expect(result["kept"] as? Bool == true)
        #expect(result["privacy"] as? Bool == true)
    }

    @Test(arguments: [true, false])
    func privacyExistsOnlyForExtensionsThatAskForIt(declared: Bool) async throws {
        let result = try await run(setup: """
        const browser = { runtime: { getManifest: () => ({ permissions: \(declared ? #"["privacy"]"# : "[]") }) } };
        """, body: """
        return {
            present: "privacy" in browser,
            setting: browser.privacy ? browser.privacy.services.passwordSavingEnabled === undefined : null
        };
        """)
        #expect(result["present"] as? Bool == declared)
        if declared {
            #expect(result["setting"] as? Bool == true)
        }
    }

    @Test func unavailableDownloadsAreNotSentToTheNativePermissionCheck() async throws {
        let result = try await run(setup: """
        let calls = 0;
        const browser = { permissions: {
            contains: async () => { calls++; throw new Error("Unsupported permission"); },
            request: async () => false
        }};
        """, body: """
        const granted = await browser.permissions.contains({permissions: ["storage", "downloads"]});
        return {granted, calls};
        """)
        #expect(result["granted"] as? Bool == false)
        #expect(result["calls"] as? Int == 0)
    }

    @Test func availableDownloadsAndOtherPermissionsStillUseNativeAnswers() async throws {
        let result = try await run(setup: """
        const queries = [];
        const browser = { downloads: {}, permissions: {
            contains: async query => { queries.push(query); return query.permissions[0] === "storage"; },
            request: async () => true
        }};
        """, body: """
        const downloads = await browser.permissions.contains({permissions: ["downloads"]});
        delete browser.downloads;
        const storage = await browser.permissions.contains({permissions: ["storage"]});
        const requested = await browser.permissions.request({permissions: ["downloads"]});
        return {downloads, storage, requested, calls: queries.length};
        """)
        #expect(result["downloads"] as? Bool == false)
        #expect(result["storage"] as? Bool == true)
        #expect(result["requested"] as? Bool == true)
        #expect(result["calls"] as? Int == 2)
    }

    @Test(arguments: ["action", "browserAction"])
    func dualIconSourcesUseThePathWithoutChangingTheCaller(namespace: String) async throws {
        let result = try await run(setup: """
        let received;
        const action = { setIcon(details, callback) {
            if ("path" in details && "imageData" in details) throw new Error("Two icon sources");
            received = details;
            callback();
            return Promise.resolve("set");
        }};
        const browser = { ["\(namespace)"]: action };
        """, body: """
        const original = {path: {16: "icon.png"}, imageData: {16: {}}, tabId: 7};
        let callbackCalled = false;
        const answer = await action.setIcon(original, () => { callbackCalled = true; });
        return {
            answer, callbackCalled, tabId: received.tabId, path: received.path[16],
            receivedPixels: "imageData" in received, originalPixels: "imageData" in original
        };
        """)
        #expect(result["answer"] as? String == "set")
        #expect(result["callbackCalled"] as? Bool == true)
        #expect(result["tabId"] as? Int == 7)
        #expect(result["path"] as? String == "icon.png")
        #expect(result["receivedPixels"] as? Bool == false)
        #expect(result["originalPixels"] as? Bool == true)
    }

    @Test func pixelIconsAndNativeFailuresArePreserved() async throws {
        let result = try await run(setup: """
        const received = [];
        const action = { setIcon: async details => {
            if (details.tabId === -1) throw new Error("Unknown tab");
            received.push(details);
        }};
        const browser = {action, browserAction: action};
        """, body: """
        const pixels = {imageData: {16: {}}};
        await action.setIcon(pixels);
        await action.setIcon({path: undefined, imageData: pixels.imageData});
        let failure;
        try { await action.setIcon({path: "icon.png", tabId: -1}); }
        catch (error) { failure = error.message; }
        return {
            sameObject: received[0] === pixels,
            hasPath: "path" in received[1],
            samePixels: received[1].imageData === pixels.imageData,
            failure
        };
        """)
        #expect(result["sameObject"] as? Bool == true)
        #expect(result["hasPath"] as? Bool == false)
        #expect(result["samePixels"] as? Bool == true)
        #expect(result["failure"] as? String == "Unknown tab")
    }
}

@MainActor
@Suite(.boundedWebViews)
struct ExtensionShimWorkerTests {
    @Test func aWorkerThatListensForMissingEventsStarts() async throws {
        let package = TestFiles.directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let scripts = package.appendingPathComponent("bg", isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: package) }
        let manifest: [String: Any] = [
            "manifest_version": 3, "name": "Worker test", "version": "1.0",
            "description": "Starts a worker that uses missing events.",
            "permissions": ["webNavigation", "privacy", "sidePanel", "storage"],
            "background": ["service_worker": "bg/sw.js"],
        ]
        try JSONSerialization.data(withJSONObject: manifest)
            .write(to: package.appendingPathComponent("manifest.json"))
        try "self.libraryLoaded = true;"
            .write(to: scripts.appendingPathComponent("lib.js"), atomically: true, encoding: .utf8)
        try """
        importScripts("lib.js");
        if (self.libraryLoaded !== true) throw new Error("lib.js did not load");
        chrome.webNavigation.onHistoryStateUpdated.addListener(() => {});
        chrome.webNavigation.onTabReplaced.addListener(() => {});
        chrome.privacy.services.passwordSavingEnabled && chrome.privacy.services.passwordSavingEnabled.get({});
        chrome.windows.onBoundsChanged.addListener(() => {});
        chrome.runtime.onSuspendCanceled.addListener(() => {});
        chrome.storage.managed.get(null).then(policy => { self.policy = policy; });
        chrome.sidePanel.setPanelBehavior({ openPanelOnActionClick: true }).catch(() => {});
        """.write(to: scripts.appendingPathComponent("sw.js"), atomically: true, encoding: .utf8)

        #expect(ExtensionShims.ensureApplied(at: package))
        let controller = WKWebExtensionController(configuration: .nonPersistent())
        let webExtension = try await WKWebExtension(resourceBaseURL: package)
        let context = WKWebExtensionContext(for: webExtension)
        for permission in webExtension.requestedPermissions {
            context.setPermissionStatus(.grantedExplicitly, for: permission)
        }
        try controller.load(context)
        defer { try? controller.unload(context) }

        var started = false
        let start = Task { @MainActor in
            try? await context.loadBackgroundContent()
            started = true
        }
        defer { start.cancel() }
        let settled = await waitUntil(timeout: .seconds(15)) { started || !context.errors.isEmpty }
        #expect(settled)
        #expect(started)
        #expect(context.errors.isEmpty, "\(context.errors.map(\.localizedDescription))")
    }

    @Test func anOptionsPageThatReadsAMissingAPILoads() async throws {
        let package = TestFiles.directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: package) }
        let manifest: [String: Any] = [
            "manifest_version": 3, "name": "Page test", "version": "1.0",
            "description": "Opens a page that reads a missing API.",
            "permissions": ["privacy", "storage"],
            "options_ui": ["page": "options.html"],
        ]
        try JSONSerialization.data(withJSONObject: manifest)
            .write(to: package.appendingPathComponent("manifest.json"))
        try #"<!doctype html><html><head><script src="options.js"></script></head><body></body></html>"#
            .write(to: package.appendingPathComponent("options.html"), atomically: true, encoding: .utf8)
        try """
        const saving = chrome.privacy.services.passwordSavingEnabled;
        chrome.storage.managed.get(null).then(() => { document.documentElement.dataset.ready = String(saving === undefined); });
        """.write(to: package.appendingPathComponent("options.js"), atomically: true, encoding: .utf8)

        #expect(ExtensionShims.ensurePagesApplied(at: package) == 1)
        let controller = WKWebExtensionController(configuration: .nonPersistent())
        let webExtension = try await WKWebExtension(resourceBaseURL: package)
        let context = WKWebExtensionContext(for: webExtension)
        for permission in webExtension.requestedPermissions {
            context.setPermissionStatus(.grantedExplicitly, for: permission)
        }
        try controller.load(context)
        defer { try? controller.unload(context) }

        let view = WKWebView(frame: .zero, configuration: try #require(context.webViewConfiguration))
        view.load(URLRequest(url: context.baseURL.appendingPathComponent("options.html")))
        var ready: String?
        let loaded = await waitUntil(timeout: .seconds(15)) {
            ready = try? await view.evaluateJavaScript("document.documentElement.dataset.ready ?? null") as? String
            return ready != nil
        }
        #expect(loaded)
        #expect(ready == "true")
        #expect(context.errors.isEmpty, "\(context.errors.map(\.localizedDescription))")
    }
}
