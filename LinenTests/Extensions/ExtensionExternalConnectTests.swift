// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

struct ExtensionExternalConnectTests {
    private func scratchPackage(manifest: [String: Any]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: manifest)
        try data.write(to: directory.appendingPathComponent("manifest.json"))
        return directory
    }

    private func contentScripts(at package: URL) throws -> [[String: Any]] {
        let data = try Data(contentsOf: package.appendingPathComponent("manifest.json"))
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return root?["content_scripts"] as? [[String: Any]] ?? []
    }

    @Test func aConnectableExtensionGetsARelayOnItsOwnSites() throws {
        let package = try scratchPackage(manifest: [
            "manifest_version": 3,
            "externally_connectable": ["matches": ["*://*.twitch.tv/*"]],
            "content_scripts": [["js": ["own.js"], "matches": ["*://*.twitch.tv/*"]]],
        ])
        defer { try? FileManager.default.removeItem(at: package) }

        #expect(ExtensionExternalConnect.ensureRelayApplied(at: package))
        let scripts = try contentScripts(at: package)
        #expect(scripts.count == 2)
        #expect(scripts[0]["js"] as? [String] == ["own.js"])
        let relay = try #require(scripts.last)
        #expect(relay["js"] as? [String] == [ExtensionExternalConnect.relayFileName])
        #expect(relay["matches"] as? [String] == ["*://*.twitch.tv/*"])
        #expect(relay["run_at"] as? String == "document_start")
        #expect(relay["all_frames"] as? Bool == true)
        let file = package.appendingPathComponent(ExtensionExternalConnect.relayFileName)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func applyingTwiceAddsOneRelay() throws {
        let package = try scratchPackage(manifest: [
            "manifest_version": 3,
            "externally_connectable": ["matches": ["<all_urls>"]],
        ])
        defer { try? FileManager.default.removeItem(at: package) }

        #expect(ExtensionExternalConnect.ensureRelayApplied(at: package))
        let once = try Data(contentsOf: package.appendingPathComponent("manifest.json"))
        #expect(ExtensionExternalConnect.ensureRelayApplied(at: package))
        let twice = try Data(contentsOf: package.appendingPathComponent("manifest.json"))
        #expect(once == twice)
        #expect(try contentScripts(at: package).count == 1)
    }

    @Test func anExtensionThatIsNotConnectableIsLeftAlone() throws {
        let package = try scratchPackage(manifest: [
            "manifest_version": 3,
            "content_scripts": [["js": ["own.js"], "matches": ["<all_urls>"]]],
        ])
        defer { try? FileManager.default.removeItem(at: package) }

        #expect(!ExtensionExternalConnect.ensureRelayApplied(at: package))
        #expect(try contentScripts(at: package).count == 1)
        let file = package.appendingPathComponent(ExtensionExternalConnect.relayFileName)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
