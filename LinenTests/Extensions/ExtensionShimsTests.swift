// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

struct ExtensionShimsTests {
    private func scratchPackage(manifest: [String: Any]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
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

    @Test func aServiceWorkerManifestIsLeftAlone() throws {
        let package = try scratchPackage(manifest: [
            "manifest_version": 3,
            "background": ["service_worker": "sw.js"],
        ])
        defer { try? FileManager.default.removeItem(at: package) }

        #expect(!ExtensionShims.ensureApplied(at: package))
        let data = try Data(contentsOf: package.appendingPathComponent("manifest.json"))
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let background = root?["background"] as? [String: Any]
        #expect(background?["service_worker"] as? String == "sw.js")
        #expect(background?["scripts"] == nil)
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
}

@MainActor
@Suite(.boundedWebViews)
struct ExtensionShimRuntimeTests {
    private func run(setup: String, body: String) async throws -> [String: Any] {
        let configuration = WebViewPool.makeConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.loadHTMLString("<!doctype html><title>Shim test</title>", baseURL: nil)
        try #require(await PageSettle.untilIdle(view, timeout: .seconds(20)))
        let result = try await view.callAsyncJavaScript(
            setup + "\n" + ExtensionShims.source + "\n" + body,
            arguments: [:], in: nil, contentWorld: .page
        )
        return try #require(result as? [String: Any])
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
