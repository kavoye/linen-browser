// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

@MainActor
@Observable
final class ProfileStore {
    static let shared = ProfileStore()

    @ObservationIgnored private var catalog: ProfileStore?
    private var storedProfiles: [Profile]
    private(set) var profiles: [Profile] {
        get {
            catalog?.profiles ?? storedProfiles
        }
        set {
            if let catalog {
                catalog.profiles = newValue
            } else {
                storedProfiles = newValue
            }
        }
    }

    static func selection(profile: Profile, catalog: ProfileStore = .shared) -> ProfileStore {
        let selection = ProfileStore(file: catalog.file)
        selection.catalog = catalog
        selection.markCurrent(profile)
        return selection
    }
    private(set) var currentID: UUID

    private let file: URL

    let privateBrowsing = Profile.privateBrowsing()

    private(set) var lastPersistentID: UUID

    private var storedLaunchProfileID: UUID?
    private(set) var launchProfileID: UUID? {
        get {
            if let catalog {
                return catalog.launchProfileID
            }
            return storedLaunchProfileID
        }
        set {
            if let catalog {
                catalog.launchProfileID = newValue
            } else {
                storedLaunchProfileID = newValue
            }
        }
    }

    private var storedLastUsed: [UUID: Date] = [:]
    private(set) var lastUsed: [UUID: Date] {
        get {
            catalog?.lastUsed ?? storedLastUsed
        }
        set {
            if let catalog {
                catalog.lastUsed = newValue
            } else {
                storedLastUsed = newValue
            }
        }
    }

    var current: Profile {
        if currentID == Profile.privateID {
            return privateBrowsing
        }
        return profiles.first { $0.id == currentID } ?? profiles[0]
    }

    var isPrivate: Bool {
        currentID == Profile.privateID
    }

    var profileToReturnTo: Profile {
        profiles.first { $0.id == lastPersistentID } ?? profiles[0]
    }

    var hasMultiple: Bool {
        profiles.count > 1
    }

    init(file: URL? = nil) {
        self.file = file ?? Self.defaultFile
        let stored = (try? Data(contentsOf: self.file))
            .flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        var loaded = stored?.profiles ?? []
        if !loaded.contains(where: { $0.isOriginal }) {
            loaded.insert(.original(), at: 0)
        }
        storedProfiles = loaded
        let remembered = stored.map(\.currentID).flatMap { id in
            loaded.contains { $0.id == id } ? id : nil
        }
        let pinned = stored?.launchProfileID.flatMap { id in
            loaded.contains { $0.id == id } ? id : nil
        }
        let opening = pinned ?? remembered ?? Profile.originalID
        storedLaunchProfileID = pinned
        currentID = opening
        lastPersistentID = opening
        storedLastUsed = (stored?.lastUsed ?? [:]).filter { id, _ in
            loaded.contains { $0.id == id }
        }
    }

    // MARK: - Changing the list

    @discardableResult
    func add(name: String, symbol: String = "person", color: TabFolderColor = .gray) -> Profile {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = Profile(
            id: UUID(),
            name: trimmed.isEmpty ? String(localized: "New Profile") : trimmed,
            symbol: symbol,
            color: color
        )
        profiles.append(profile)
        save()
        return profile
    }

    func rename(_ profile: Profile, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = index(of: profile) else { return }
        profiles[index].name = trimmed
        save()
    }

    func setAppearance(of profile: Profile, symbol: String, color: TabFolderColor) {
        guard let index = index(of: profile) else { return }
        profiles[index].symbol = symbol
        profiles[index].color = color
        save()
    }

    func move(_ profile: Profile, to destination: Int) {
        guard let index = index(of: profile) else { return }
        let bounded = min(max(destination, 0), profiles.count - 1)
        guard bounded != index else { return }
        let moved = profiles.remove(at: index)
        profiles.insert(moved, at: bounded)
        save()
    }

    func setLaunchProfile(_ id: UUID?) {
        let resolved = id.flatMap { candidate in
            profiles.contains { $0.id == candidate } ? candidate : nil
        }
        guard resolved != launchProfileID else { return }
        launchProfileID = resolved
        save()
    }

    var deletableProfiles: [Profile] {
        profiles.filter { !$0.isOriginal }
    }

    func remove(_ profile: Profile) async {
        guard !profile.isOriginal, let index = index(of: profile) else { return }
        profiles.remove(at: index)
        if currentID == profile.id {
            currentID = Profile.originalID
        }
        if launchProfileID == profile.id {
            launchProfileID = nil
        }
        lastUsed[profile.id] = nil
        BrowserProfileContext.forget(profile.id)
        save()
        await Profile.erase(profile)
    }

    func markCurrent(_ profile: Profile) {
        if profile.isPrivate {
            currentID = Profile.privateID
            return
        }
        guard profiles.contains(where: { $0.id == profile.id }) else { return }
        currentID = profile.id
        lastPersistentID = profile.id
        lastUsed[profile.id] = Date()
        save()
    }

    // MARK: - Storage

    private func index(of profile: Profile) -> Int? {
        profiles.firstIndex { $0.id == profile.id }
    }

    private nonisolated struct Stored: Codable, Sendable {
        var profiles: [Profile]
        var currentID: UUID
        var launchProfileID: UUID?
        var lastUsed: [UUID: Date]?
    }

    private func save() {
        if let catalog {
            if !isPrivate {
                catalog.currentID = currentID
                catalog.lastPersistentID = lastPersistentID
            }
            catalog.save()
            return
        }
        JSONFileStore.encodeAndWrite(
            Stored(
                profiles: profiles,
                currentID: currentID,
                launchProfileID: launchProfileID,
                lastUsed: lastUsed
            ),
            to: file,
            sortedKeys: true
        )
    }

    private static var defaultFile: URL {
        AppDatabase.supportDirectory.appendingPathComponent("profiles.json")
    }
}
