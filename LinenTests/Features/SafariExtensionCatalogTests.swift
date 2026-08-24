// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

struct SafariExtensionCatalogTests {
    private func makeApp(
        named name: String,
        in root: URL,
        extensionPoint: String?,
        bundleID: String = "com.example.Thing.Extension"
    ) throws -> URL {
        let app = root.appending(path: "\(name).app", directoryHint: .isDirectory)
        let appex = app.appending(path: "Contents/PlugIns/Thing.appex", directoryHint: .isDirectory)
        let contents = appex.appending(path: "Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)

        var info: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleShortVersionString": "3.2",
        ]
        if let extensionPoint {
            info["NSExtension"] = ["NSExtensionPointIdentifier": extensionPoint]
        }
        let data = try PropertyListSerialization.data(
            fromPropertyList: info, format: .xml, options: 0
        )
        try data.write(to: contents.appending(path: "Info.plist"))
        return app
    }

    private func sandbox() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "safari-cat-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func aSafariWebExtensionIsFound() throws {
        let root = try sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeApp(named: "Dark Reader", in: root, extensionPoint: "com.apple.Safari.web-extension")

        let found = SafariExtensionCatalog.installed(in: [root])

        #expect(found.map(\.displayName) == ["Dark Reader"])
        #expect(found.first?.version == "3.2")
        #expect(found.first?.id == "com.example.Thing.Extension")
    }

    @Test func theLegacyNativeKindIsSkipped() throws {
        let root = try sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeApp(named: "BetterJSON", in: root, extensionPoint: "com.apple.Safari.extension")

        #expect(SafariExtensionCatalog.installed(in: [root]).isEmpty)
    }

    @Test func anAppWithNoExtensionIsIgnored() throws {
        let root = try sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeApp(named: "Plain", in: root, extensionPoint: nil)

        #expect(SafariExtensionCatalog.installed(in: [root]).isEmpty)
    }

    @Test func anAppInASubfolderIsStillFound() throws {
        let root = try sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appending(path: "Utilities", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        _ = try makeApp(named: "Tucked Away", in: nested, extensionPoint: "com.apple.Safari.web-extension")

        #expect(SafariExtensionCatalog.installed(in: [root]).map(\.displayName) == ["Tucked Away"])
    }

    @Test func theSameExtensionIsNotListedTwice() throws {
        let root = try sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeApp(named: "One", in: root, extensionPoint: "com.apple.Safari.web-extension")
        _ = try makeApp(named: "Two", in: root, extensionPoint: "com.apple.Safari.web-extension")

        #expect(SafariExtensionCatalog.installed(in: [root]).count == 1)
    }
}
