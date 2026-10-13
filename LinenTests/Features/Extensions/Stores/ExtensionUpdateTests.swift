// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized)
struct ExtensionUpdateTests {
    private let key = "extensions.lastUpdateCheck"

    private func scratchDefaults() -> UserDefaults {
        let suite = TestDefaults.name("com.kavoye.Linen.tests")
        return UserDefaults(suiteName: suite) ?? .standard
    }

    private func manager(_ defaults: UserDefaults) -> ExtensionManager {
        ExtensionManager.defaults = defaults
        return ExtensionManager(browser: BrowserModel(database: .temporary()))
    }

    @Test func theFirstLaunchOfTheDayTakesTheSweep() async {
        let defaults = scratchDefaults()
        defer { ExtensionManager.defaults = .standard }
        let extensions = manager(defaults)

        await extensions.updateInstalledIfDue()

        #expect(defaults.object(forKey: key) is Date, "the sweep records when it ran")
    }

    @Test func aSweepAnHourOldIsNotDueAgain() async {
        let defaults = scratchDefaults()
        defer { ExtensionManager.defaults = .standard }
        let anHourAgo = Date().addingTimeInterval(-3_600)
        defaults.set(anHourAgo, forKey: key)
        let extensions = manager(defaults)

        await extensions.updateInstalledIfDue()

        #expect(defaults.object(forKey: key) as? Date == anHourAgo, "the stamp is left where it was")
    }

    @Test func aSweepFromYesterdayIsDue() async {
        let defaults = scratchDefaults()
        defer { ExtensionManager.defaults = .standard }
        let yesterday = Date().addingTimeInterval(-90_000)
        defaults.set(yesterday, forKey: key)
        let extensions = manager(defaults)

        await extensions.updateInstalledIfDue()

        let stamped = defaults.object(forKey: key) as? Date
        #expect(stamped != nil)
        #expect((stamped ?? .distantPast) > yesterday, "a day later the sweep runs again")
    }

    @Test func theSweepJudgesTheClockItIsGiven() async {
        let defaults = scratchDefaults()
        defer { ExtensionManager.defaults = .standard }
        let now = Date()
        defaults.set(now, forKey: key)
        let extensions = manager(defaults)

        await extensions.updateInstalledIfDue(now: now.addingTimeInterval(60))
        #expect(defaults.object(forKey: key) as? Date == now)

        await extensions.updateInstalledIfDue(now: now.addingTimeInterval(86_401))
        #expect(defaults.object(forKey: key) as? Date != now)
    }

    @Test func anExtensionThatIsNotInstalledIsNotChecked() async {
        let defaults = scratchDefaults()
        defer { ExtensionManager.defaults = .standard }
        let extensions = manager(defaults)

        await extensions.checkForUpdate(id: "not-installed")

        #expect(extensions.updateChecks["not-installed"] == nil, "nothing to report about nothing")
    }

    private func webExtension(_ manifest: String) async throws -> WKWebExtension {
        let package = TestFiles.directory
            .appendingPathComponent("linen-ext-update-access-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: package) }
        try Data(#"{"manifest_version":3,"name":"Update","version":"1.0",\#(manifest)}"#.utf8)
            .write(to: package.appendingPathComponent("manifest.json"))
        return try await WKWebExtension(resourceBaseURL: package)
    }

    @Test func anUpdateAskingForTheSameAccessAddsNothing() async throws {
        let manifest = #""permissions":["storage"],"host_permissions":["*://*.twitch.tv/*"]"#
        let added = ExtensionManager.access(
            in: try await webExtension(manifest),
            beyond: try await webExtension(manifest)
        )
        #expect(added.isEmpty)
    }

    @Test func anUpdateAskingForEveryWebsiteAddsWebsites() async throws {
        let added = ExtensionManager.access(
            in: try await webExtension(#""host_permissions":["*://*.twitch.tv/*","<all_urls>"]"#),
            beyond: try await webExtension(#""host_permissions":["*://*.twitch.tv/*"]"#)
        )
        #expect(added.permissions.isEmpty)
        #expect(added.websites.count == 1)
        #expect(added.websites.first?.matchesAllURLs == true)
    }

    @Test func aWebsiteInsideAnApprovedPatternIsNotNew() async throws {
        let added = ExtensionManager.access(
            in: try await webExtension(#""host_permissions":["*://clips.twitch.tv/*"]"#),
            beyond: try await webExtension(#""host_permissions":["<all_urls>"]"#)
        )
        #expect(added.isEmpty)
    }

    @Test func aContentScriptOnANewWebsiteCounts() async throws {
        let added = ExtensionManager.access(
            in: try await webExtension(#""content_scripts":[{"matches":["*://*.example.com/*"],"js":["a.js"]}]"#),
            beyond: try await webExtension(#""host_permissions":["*://*.twitch.tv/*"]"#)
        )
        #expect(added.websites.map(\.string) == ["*://*.example.com/*"])
    }

    @Test func anUpdateAskingForANewPermissionAddsIt() async throws {
        let added = ExtensionManager.access(
            in: try await webExtension(#""permissions":["storage","cookies"]"#),
            beyond: try await webExtension(#""permissions":["storage"]"#)
        )
        #expect(added.permissions.map(\.rawValue) == ["cookies"])
        #expect(added.websites.isEmpty)
    }

    @Test func requestedWebsitesIncludeExternallyConnectableOnes() async throws {
        let webExtension = try await webExtension(#"""
        "host_permissions":["*://*.twitch.tv/*"],"externally_connectable":{"matches":["*://*.example.com/*"]}
        """#)
        let websites = Set(webExtension.allRequestedMatchPatterns.map(\.string))
        #expect(websites == ["*://*.twitch.tv/*", "*://*.example.com/*"])
    }

    @Test func anUpdateThatAddsAnExternalWebsiteAddsWebsites() async throws {
        let added = ExtensionManager.access(
            in: try await webExtension(#""externally_connectable":{"matches":["*://*.example.com/*"]}"#),
            beyond: try await webExtension(#""permissions":["storage"]"#)
        )
        #expect(added.websites.map(\.string) == ["*://*.example.com/*"])
    }

    @Test func aHeldUpdateIsRememberedUntilCleared() {
        let defaults = scratchDefaults()
        defer { ExtensionManager.defaults = .standard }
        manager(defaults).setHeldUpdate("2.0", id: "held")

        let relaunched = manager(defaults)
        #expect(relaunched.heldUpdates == ["held": "2.0"])

        relaunched.setHeldUpdate(nil, id: "held")
        #expect(manager(defaults).heldUpdates.isEmpty)
    }

    private func zippedPackage(version: String, hosts: [String]) throws -> Data {
        let files = FileManager.default
        let scratch = TestFiles.directory
            .appendingPathComponent("linen-ext-update-zip-\(UUID().uuidString)", isDirectory: true)
        let contents = scratch.appendingPathComponent("contents", isDirectory: true)
        try files.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: scratch) }
        let list = hosts.map { "\"\($0)\"" }.joined(separator: ",")
        try Data(#"{"manifest_version":3,"name":"Update","version":"\#(version)","host_permissions":[\#(list)]}"#.utf8)
            .write(to: contents.appendingPathComponent("manifest.json"))
        let archive = scratch.appendingPathComponent("package.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--norsrc", contents.path, archive.path]
        try process.run()
        process.waitUntilExit()
        return try Data(contentsOf: archive)
    }

    private struct Installed {
        let manager: ExtensionManager
        let browser: BrowserModel
        let directory: URL

        func tearDown() {
            manager.unregister(browser: browser)
            browser.closeAllTabs(saving: false)
            try? FileManager.default.removeItem(at: directory)
            ExtensionManager.defaults = .standard
            ExtensionManager.downloadPackage = ExtensionManager.downloadPackageFromStore
        }
    }

    private func installVersionOne(
        id: String,
        serving update: Data,
        defaults: UserDefaults
    ) async throws -> Installed {
        let directory = TestFiles.directory
            .appendingPathComponent("linen-ext-update-flow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let library = ExtensionLibrary(baseDirectory: directory, profile: .original())
        library.load()
        library.recordInstall(id: id)
        try await library.unpack(try zippedPackage(version: "1.0", hosts: ["*://*.twitch.tv/*"]), id: id)
        library.updateMetadata(id: id, name: "Update", version: "1.0")

        ExtensionManager.defaults = defaults
        ExtensionManager.downloadPackage = { _ in update }
        let manager = ExtensionManager(library: library)
        let browser = BrowserModel(database: .temporary())
        manager.register(browser: browser)
        await manager.start()
        return Installed(manager: manager, browser: browser, directory: directory)
    }

    @Test func aQuietUpdateAskingForMoreAccessWaitsForApproval() async throws {
        let id = "update-needs-access"
        let update = try zippedPackage(version: "2.0", hosts: ["*://*.twitch.tv/*", "<all_urls>"])
        let installed = try await installVersionOne(id: id, serving: update, defaults: scratchDefaults())
        defer { installed.tearDown() }

        await installed.manager.checkForUpdate(id: id, quietly: true)

        #expect(installed.manager.heldUpdates[id] == "2.0")
        #expect(installed.manager.installedRecord(id: id)?.version == "1.0", "the old version keeps running")
        #expect(installed.manager.updateChecks[id] == nil, "a quiet check reports nothing")
    }

    @Test func aQuietUpdateAskingForNothingNewInstalls() async throws {
        let id = "update-same-access"
        let update = try zippedPackage(version: "2.0", hosts: ["*://*.twitch.tv/*"])
        let installed = try await installVersionOne(id: id, serving: update, defaults: scratchDefaults())
        defer { installed.tearDown() }

        await installed.manager.checkForUpdate(id: id, quietly: true)

        #expect(installed.manager.installedRecord(id: id)?.version == "2.0")
        #expect(installed.manager.heldUpdates[id] == nil)
        #expect(installed.manager.updateChecks[id] == .updated("2.0"))
    }

    @Test func aHeldUpdateIsForgottenOnceTheStoreNoLongerOffersIt() async throws {
        let id = "update-withdrawn"
        let defaults = scratchDefaults()
        let installed = try await installVersionOne(
            id: id,
            serving: try zippedPackage(version: "1.0", hosts: ["*://*.twitch.tv/*"]),
            defaults: defaults
        )
        defer { installed.tearDown() }
        installed.manager.setHeldUpdate("2.0", id: id)

        await installed.manager.checkForUpdate(id: id, quietly: true)

        #expect(installed.manager.heldUpdates[id] == nil)
        #expect(ExtensionManager.savedHeldUpdates()[id] == nil, "the saved list forgets it too")
    }

    @Test func installingAHeldUpdateClearsTheHold() async throws {
        let id = "update-approved"
        let update = try zippedPackage(version: "2.0", hosts: ["*://*.twitch.tv/*"])
        let installed = try await installVersionOne(id: id, serving: update, defaults: scratchDefaults())
        defer { installed.tearDown() }
        installed.manager.setHeldUpdate("2.0", id: id)

        await installed.manager.checkForUpdate(id: id)

        #expect(installed.manager.installedRecord(id: id)?.version == "2.0")
        #expect(installed.manager.heldUpdates[id] == nil)
    }

    @Test func uninstallingForgetsAHeldUpdate() {
        let defaults = scratchDefaults()
        defer { ExtensionManager.defaults = .standard }
        let extensions = manager(defaults)
        extensions.setHeldUpdate("2.0", id: "held")

        extensions.uninstall(id: "held")

        #expect(manager(defaults).heldUpdates.isEmpty)
    }
}
