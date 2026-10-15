// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

@MainActor
@Observable
final class SpaceStore {
    static let shared = SpaceStore()

    private(set) var spaces: [Space]

    private let file: URL

    init(file: URL? = nil) {
        self.file = file ?? Self.defaultFile
        spaces = (try? Data(contentsOf: self.file))
            .flatMap { try? JSONDecoder().decode([Space].self, from: $0) } ?? []
    }

    func space(id: UUID?) -> Space? {
        guard let id else { return nil }
        return spaces.first { $0.id == id }
    }

    func spaces(for profileID: UUID) -> [Space] {
        spaces.filter { $0.profileID == profileID }
    }

    func neighbor(of id: UUID, forward: Bool) -> Space? {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return nil }
        let next = forward ? spaces.index(after: index) : index - 1
        return spaces.indices.contains(next) ? spaces[next] : nil
    }

    func adjacent(to id: UUID) -> Space? {
        neighbor(of: id, forward: false) ?? neighbor(of: id, forward: true)
    }

    func reconcile(with profiles: [Profile]) {
        let live = Set(profiles.map(\.id))
        var next = spaces.filter { live.contains($0.profileID) }
        for profile in profiles where !next.contains(where: { $0.profileID == profile.id }) {
            next.append(Space(
                id: UUID(),
                name: profile.name,
                symbol: profile.symbol,
                color: profile.color,
                profileID: profile.id
            ))
        }
        guard next != spaces else { return }
        spaces = next
        save()
    }

    @discardableResult
    func add(name: String, symbol: String, color: TabFolderColor, profileID: UUID) -> Space {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let space = Space(
            id: UUID(),
            name: trimmed.isEmpty ? String(localized: "New Space") : trimmed,
            symbol: symbol,
            color: color,
            profileID: profileID
        )
        spaces.append(space)
        save()
        return space
    }

    func update(_ space: Space) {
        guard let index = spaces.firstIndex(where: { $0.id == space.id }) else { return }
        var updated = space
        let trimmed = space.name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.name = trimmed.isEmpty ? spaces[index].name : trimmed
        updated.profileID = spaces[index].profileID
        guard updated != spaces[index] else { return }
        spaces[index] = updated
        save()
    }

    func canRemove(_ space: Space) -> Bool {
        spaces.count > 1 && (space.profileID != Profile.originalID || spaces(for: Profile.originalID).count > 1)
    }

    func ownsLastSpace(of space: Space) -> Bool {
        spaces(for: space.profileID).count == 1
    }

    func remove(_ space: Space) {
        guard canRemove(space) else { return }
        spaces.removeAll { $0.id == space.id }
        save()
    }

    private func save() {
        JSONFileStore.encodeAndWrite(spaces, to: file, sortedKeys: true)
    }

    private static var defaultFile: URL {
        AppDatabase.supportDirectory.appendingPathComponent("spaces.json")
    }
}
