// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// The shim rides in front of an extension's background scripts and fills
/// the APIs WebKit is missing.
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
}
