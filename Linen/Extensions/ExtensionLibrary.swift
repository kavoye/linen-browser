// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

struct InstalledExtension: Codable, Identifiable, Equatable {
    var id: String
    var displayName: String
    var version: String
    var enabled: Bool
    var installedAt: Date
    var isPinned: Bool
    var toolbarOrder: Int

    init(
        id: String,
        displayName: String,
        version: String,
        enabled: Bool,
        installedAt: Date,
        isPinned: Bool = true,
        toolbarOrder: Int = 0
    ) {
        self.id = id
        self.displayName = displayName
        self.version = version
        self.enabled = enabled
        self.installedAt = installedAt
        self.isPinned = isPinned
        self.toolbarOrder = toolbarOrder
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        version = try container.decode(String.self, forKey: .version)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        installedAt = try container.decode(Date.self, forKey: .installedAt)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? true
        toolbarOrder = try container.decodeIfPresent(Int.self, forKey: .toolbarOrder) ?? .max
    }
}

@MainActor
final class ExtensionLibrary {
    private struct Index: Codable {
        var records: [InstalledExtension] = []
    }

    enum PackageError: LocalizedError {
        case unpackingFailed
        case noManifest

        var errorDescription: String? {
            switch self {
            case .unpackingFailed:
                String(localized: "This extension’s package couldn’t be unpacked")
            case .noManifest:
                String(localized: "This extension’s package has no manifest")
            }
        }
    }

    private var index = Index()
    private nonisolated let baseDirectory: URL

    var records: [InstalledExtension] {
        index.records
    }

    init(baseDirectory: URL = ExtensionLibrary.defaultBaseDirectory) {
        self.baseDirectory = baseDirectory
    }

    static var defaultBaseDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Linen", isDirectory: true)
            .appendingPathComponent("Extensions", isDirectory: true)
    }

    private var indexURL: URL {
        baseDirectory.appendingPathComponent("installed.json")
    }

    nonisolated func packageURL(for id: String) -> URL {
        baseDirectory.appendingPathComponent(id, isDirectory: true)
    }

    func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode(Index.self, from: data) else { return }
        index = decoded
        normalizeOrder()
        sweep(includingStaging: true)
    }

    private func sweep(includingStaging: Bool = false) {
        let files = FileManager.default
        guard let contents = try? files.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        let keep = Set(index.records.map(\.id)).union([indexURL.lastPathComponent])
        for item in contents {
            let name = item.lastPathComponent
            guard !keep.contains(name) else { continue }
            guard includingStaging || !name.contains(".unpacking") else { continue }
            try? files.removeItem(at: item)
            Pipeline.log.notice("ext: removed stale \(name, privacy: .public)")
        }
    }

    nonisolated func unpack(_ zip: Data, id: String) async throws {
        let files = FileManager.default
        try files.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        let archive = baseDirectory.appendingPathComponent("\(id).unpacking.zip")
        let staging = baseDirectory.appendingPathComponent("\(id).unpacking", isDirectory: true)
        try? files.removeItem(at: staging)
        try zip.write(to: archive, options: .atomic)
        defer {
            try? files.removeItem(at: archive)
            try? files.removeItem(at: staging)
        }

        try Self.extract(archive, to: staging)
        guard files.fileExists(atPath: staging.appendingPathComponent("manifest.json").path) else {
            throw PackageError.noManifest
        }

        let destination = packageURL(for: id)
        if files.fileExists(atPath: destination.path) {
            _ = try files.replaceItemAt(destination, withItemAt: staging)
        } else {
            try files.moveItem(at: staging, to: destination)
        }
    }

    func recordInstall(id: String) {
        upsertRecord(id: id, name: id, version: "")
        save()
        sweep()
    }

    private nonisolated static func extract(_ archive: URL, to directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, directory.path]
        let complaints = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = complaints
        try process.run()
        let message = complaints.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            Pipeline.log.error("""
                ext: ditto exited \(process.terminationStatus, privacy: .public): \
                \(String(decoding: message, as: UTF8.self), privacy: .public)
                """)
            throw PackageError.unpackingFailed
        }
    }

    func updateMetadata(id: String, name: String?, version: String?) {
        guard let at = index.records.firstIndex(where: { $0.id == id }) else { return }
        if let name, !name.isEmpty {
            index.records[at].displayName = name
        }
        if let version, !version.isEmpty {
            index.records[at].version = version
        }
        save()
    }

    func setEnabled(_ enabled: Bool, id: String) {
        guard let at = index.records.firstIndex(where: { $0.id == id }) else { return }
        index.records[at].enabled = enabled
        save()
    }

    func setPinned(_ pinned: Bool, id: String) {
        guard let at = index.records.firstIndex(where: { $0.id == id }),
              index.records[at].isPinned != pinned else { return }
        index.records[at].isPinned = pinned
        save()
    }

    func move(_ id: String, before anchor: String?) {
        guard let from = index.records.firstIndex(where: { $0.id == id }) else { return }
        let record = index.records.remove(at: from)
        let to = anchor.flatMap { id in index.records.firstIndex { $0.id == id } }
            ?? index.records.count
        index.records.insert(record, at: to)
        renumber()
        save()
    }

    func uninstall(id: String) {
        index.records.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: packageURL(for: id))
        renumber()
        save()
        sweep()
    }

    private func upsertRecord(id: String, name: String, version: String) {
        if let at = index.records.firstIndex(where: { $0.id == id }) {
            index.records[at].displayName = name
            index.records[at].version = version
        } else {
            index.records.append(InstalledExtension(
                id: id,
                displayName: name,
                version: version,
                enabled: true,
                installedAt: Date(),
                toolbarOrder: index.records.count
            ))
        }
    }

    private func renumber() {
        for at in index.records.indices {
            index.records[at].toolbarOrder = at
        }
    }

    private func normalizeOrder() {
        let sorted = index.records.enumerated()
            .sorted { left, right in
                left.element.toolbarOrder == right.element.toolbarOrder
                    ? left.offset < right.offset
                    : left.element.toolbarOrder < right.element.toolbarOrder
            }
            .map(\.element)
        let alreadyInOrder = sorted.enumerated().allSatisfy { $0.element.toolbarOrder == $0.offset }
        index.records = sorted
        renumber()
        if !alreadyInOrder {
            save()
        }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
