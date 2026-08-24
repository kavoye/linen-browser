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
    private nonisolated struct CatalogueEntry: Codable, Equatable {
        var id: String
        var displayName: String
        var version: String
        var installedAt: Date
    }

    private nonisolated struct Placement: Codable, Equatable {
        var enabled: Bool
        var isPinned: Bool
        var toolbarOrder: Int
    }

    private nonisolated struct Catalogue: Codable {
        var entries: [CatalogueEntry] = []
    }

    private nonisolated struct Placements: Codable {
        var profiles: [String: [String: Placement]] = [:]
    }

    private nonisolated struct LegacyIndex: Codable {
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

    private var catalogue = Catalogue()
    private var placements = Placements()
    private nonisolated let baseDirectory: URL
    private let profileKey: String

    var records: [InstalledExtension] {
        arranged(forProfile: profileKey)
    }

    private func arranged(forProfile key: String) -> [InstalledExtension] {
        let mine = placements.profiles[key] ?? [:]
        var listed: [(record: InstalledExtension, offset: Int)] = []
        listed.reserveCapacity(catalogue.entries.count)
        for (offset, entry) in catalogue.entries.enumerated() {
            let placement = mine[entry.id]
            let record = InstalledExtension(
                id: entry.id,
                displayName: entry.displayName,
                version: entry.version,
                enabled: placement?.enabled ?? false,
                installedAt: entry.installedAt,
                isPinned: placement?.isPinned ?? true,
                toolbarOrder: placement?.toolbarOrder ?? offset
            )
            listed.append((record, offset))
        }
        listed.sort { left, right in
            left.record.toolbarOrder == right.record.toolbarOrder
                ? left.offset < right.offset
                : left.record.toolbarOrder < right.record.toolbarOrder
        }
        return listed.map(\.record)
    }

    init(
        baseDirectory: URL = ExtensionLibrary.defaultBaseDirectory,
        profile: Profile = .original()
    ) {
        self.baseDirectory = baseDirectory
        profileKey = profile.id.uuidString
    }

    static var defaultBaseDirectory: URL {
        AppDatabase.supportDirectory.appendingPathComponent("Extensions", isDirectory: true)
    }

    private var catalogueURL: URL {
        baseDirectory.appendingPathComponent("library.json")
    }

    private var placementsURL: URL {
        baseDirectory.appendingPathComponent("profiles.json")
    }

    private var legacyIndexURL: URL {
        baseDirectory.appendingPathComponent("installed.json")
    }

    nonisolated func packageURL(for id: String) -> URL {
        baseDirectory.appendingPathComponent(id, isDirectory: true)
    }

    func load() {
        if let data = try? Data(contentsOf: catalogueURL),
           let decoded = try? JSONDecoder().decode(Catalogue.self, from: data) {
            catalogue = decoded
        }
        if let data = try? Data(contentsOf: placementsURL),
           let decoded = try? JSONDecoder().decode(Placements.self, from: data) {
            placements = decoded
        }
        adoptLegacyIndexIfPresent()
        if renumberEveryProfile() {
            save()
        }
        sweep(includingStaging: true)
    }

    private func adoptLegacyIndexIfPresent() {
        let files = FileManager.default
        guard catalogue.entries.isEmpty, files.fileExists(atPath: legacyIndexURL.path),
              let data = try? Data(contentsOf: legacyIndexURL),
              let legacy = try? JSONDecoder().decode(LegacyIndex.self, from: data)
        else { return }

        catalogue.entries = legacy.records.map {
            CatalogueEntry(
                id: $0.id,
                displayName: $0.displayName,
                version: $0.version,
                installedAt: $0.installedAt
            )
        }
        placements.profiles[Profile.originalID.uuidString] = Dictionary(
            uniqueKeysWithValues: legacy.records.map { record in
                (record.id, Placement(
                    enabled: record.enabled,
                    isPinned: record.isPinned,
                    toolbarOrder: record.toolbarOrder
                ))
            }
        )
        save()
        try? files.removeItem(at: legacyIndexURL)
        Pipeline.log.notice("ext: moved \(legacy.records.count) installs into the shared library")
    }

    private func sweep(includingStaging: Bool = false) {
        let files = FileManager.default
        guard let contents = try? files.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        let keep = Set(catalogue.entries.map(\.id)).union([
            catalogueURL.lastPathComponent,
            placementsURL.lastPathComponent,
        ])
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

    func discardPackage(id: String) {
        guard !catalogue.entries.contains(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: packageURL(for: id))
    }

    func recordInstall(id: String) {
        if !catalogue.entries.contains(where: { $0.id == id }) {
            catalogue.entries.append(CatalogueEntry(
                id: id,
                displayName: id,
                version: "",
                installedAt: Date()
            ))
        }
        var mine = placements.profiles[profileKey] ?? [:]
        mine[id] = Placement(
            enabled: true,
            isPinned: mine[id]?.isPinned ?? true,
            toolbarOrder: mine[id]?.toolbarOrder ?? mine.count
        )
        placements.profiles[profileKey] = mine
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
        guard let at = catalogue.entries.firstIndex(where: { $0.id == id }) else { return }
        if let name, !name.isEmpty {
            catalogue.entries[at].displayName = name
        }
        if let version, !version.isEmpty {
            catalogue.entries[at].version = version
        }
        save()
    }

    func setEnabled(_ enabled: Bool, id: String) {
        updatePlacement(id: id) { $0.enabled = enabled }
    }

    func placement(for id: String) -> (enabled: Bool, isPinned: Bool, toolbarOrder: Int) {
        let mine = placements.profiles[profileKey]?[id]
        return (mine?.enabled ?? false, mine?.isPinned ?? true, mine?.toolbarOrder ?? .max)
    }

    func setPinned(_ pinned: Bool, id: String) {
        updatePlacement(id: id) { $0.isPinned = pinned }
    }

    func move(_ id: String, before anchor: String?) {
        var ordered = records
        guard let from = ordered.firstIndex(where: { $0.id == id }) else { return }
        let record = ordered.remove(at: from)
        let to = anchor.flatMap { anchor in ordered.firstIndex { $0.id == anchor } } ?? ordered.count
        ordered.insert(record, at: to)

        var mine = placements.profiles[profileKey] ?? [:]
        for (offset, entry) in ordered.enumerated() {
            mine[entry.id] = Placement(
                enabled: mine[entry.id]?.enabled ?? entry.enabled,
                isPinned: mine[entry.id]?.isPinned ?? entry.isPinned,
                toolbarOrder: offset
            )
        }
        placements.profiles[profileKey] = mine
        save()
    }

    func uninstall(id: String) {
        catalogue.entries.removeAll { $0.id == id }
        for key in placements.profiles.keys {
            placements.profiles[key]?.removeValue(forKey: id)
        }
        try? FileManager.default.removeItem(at: packageURL(for: id))
        _ = renumberEveryProfile()
        save()
        sweep()
    }

    @discardableResult
    private func renumberEveryProfile() -> Bool {
        var changed = false
        for key in placements.profiles.keys {
            guard var mine = placements.profiles[key] else { continue }
            for (offset, record) in arranged(forProfile: key).enumerated() {
                guard mine[record.id] != nil, mine[record.id]?.toolbarOrder != offset else { continue }
                mine[record.id]?.toolbarOrder = offset
                changed = true
            }
            placements.profiles[key] = mine
        }
        return changed
    }

    private func updatePlacement(id: String, _ change: (inout Placement) -> Void) {
        let known = placement(for: id)
        var mine = placements.profiles[profileKey] ?? [:]
        var placement = mine[id] ?? Placement(
            enabled: known.enabled,
            isPinned: known.isPinned,
            toolbarOrder: known.toolbarOrder
        )
        change(&placement)
        mine[id] = placement
        placements.profiles[profileKey] = mine
        save()
    }

    func forgetThisProfile() {
        guard placements.profiles.removeValue(forKey: profileKey) != nil else { return }
        savePlacements()
    }

    nonisolated static func enabledCount(forProfile id: UUID, in baseDirectory: URL) -> Int {
        let url = baseDirectory.appendingPathComponent("profiles.json")
        guard let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(Placements.self, from: data)
        else { return 0 }
        return stored.profiles[id.uuidString]?.values.count { $0.enabled } ?? 0
    }

    private func save() {
        saveCatalogue()
        savePlacements()
    }

    private func saveCatalogue() {
        write(catalogue, to: catalogueURL)
    }

    private func savePlacements() {
        write(placements, to: placementsURL)
    }

    private func write(_ value: some Encodable, to url: URL) {
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
