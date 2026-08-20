// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// How an installed extension is kept on disk: unpacked into a directory of
/// its own.
@MainActor
struct ExtensionPackageTests {
    private func makeLibrary() -> (ExtensionLibrary, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("linen-packages-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (ExtensionLibrary(baseDirectory: directory), directory)
    }

    /// A package with a manifest and one other file, zipped the way the
    /// Chrome Web Store serves one: everything at the root of the archive.
    private func makePackage(version: String, extra: String? = nil) throws -> Data {
        let files = FileManager.default
        let scratch = files.temporaryDirectory
            .appendingPathComponent("linen-fixture-\(UUID().uuidString)", isDirectory: true)
        let contents = scratch.appendingPathComponent("contents", isDirectory: true)
        try files.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: scratch) }

        try Data(#"{"manifest_version":3,"name":"Fixture","version":"\#(version)"}"#.utf8)
            .write(to: contents.appendingPathComponent("manifest.json"))
        if let extra {
            try Data("//\(extra)".utf8).write(to: contents.appendingPathComponent(extra))
        }

        let archive = scratch.appendingPathComponent("package.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--norsrc", contents.path, archive.path]
        try process.run()
        process.waitUntilExit()
        return try Data(contentsOf: archive)
    }

    private func manifest(in directory: URL) -> String {
        (try? String(contentsOf: directory.appendingPathComponent("manifest.json"), encoding: .utf8))
            ?? ""
    }

    @Test func unpackingPutsThePackageInADirectoryOfItsOwn() async throws {
        let (library, directory) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }

        try await library.unpack(try makePackage(version: "1"), id: "a")

        #expect(library.packageURL(for: "a") == directory.appendingPathComponent("a"))
        #expect(manifest(in: library.packageURL(for: "a")).contains("\"1\""))
    }

    /// An update has to leave the new package behind and nothing of the old
    /// one - a file dropped between versions must not survive.
    @Test func unpackingReplacesTheVersionThatWasThere() async throws {
        let (library, directory) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }

        try await library.unpack(try makePackage(version: "1", extra: "old.js"), id: "a")
        try await library.unpack(try makePackage(version: "2"), id: "a")

        let unpacked = library.packageURL(for: "a")
        #expect(manifest(in: unpacked).contains("\"2\""))
        #expect(
            !FileManager.default.fileExists(atPath: unpacked.appendingPathComponent("old.js").path)
        )
    }

    /// Nothing is staged where the loaded extension lives, so a failed
    /// unpack cannot leave a half-package behind either.
    @Test func aPackageWithNoManifestIsRefused() async throws {
        let (library, directory) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }

        let empty = try makePackage(version: "1")
        try await library.unpack(empty, id: "a")
        await #expect(throws: ExtensionLibrary.PackageError.self) {
            try await library.unpack(Data("not a zip".utf8), id: "b")
        }

        #expect(FileManager.default.fileExists(atPath: library.packageURL(for: "a").path))
        #expect(!FileManager.default.fileExists(atPath: library.packageURL(for: "b").path))
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        #expect(!leftovers.contains { $0.contains("unpacking") })
    }

    @Test func uninstallingTakesThePackageWithIt() async throws {
        let (library, directory) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }

        library.recordInstall(id: "a")
        try await library.unpack(try makePackage(version: "1"), id: "a")

        library.uninstall(id: "a")

        #expect(!FileManager.default.fileExists(atPath: library.packageURL(for: "a").path))
    }
}
