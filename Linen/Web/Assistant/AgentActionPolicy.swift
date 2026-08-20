// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

@MainActor
@Observable
final class AgentActionPolicy {
    static private(set) var shared = AgentActionPolicy()

    @discardableResult
    static func use(storage: any AgentGrantStorage) -> AgentActionPolicy {
        shared = AgentActionPolicy(storage: storage)
        return shared
    }

    struct Grant: Identifiable, Hashable, Codable, Sendable {
        var host: String
        var category: SensitiveAction.Category
        var grantedAt: Date

        var id: String {
            "\(category.rawValue)|\(host)"
        }
    }

    fileprivate static let storageKey = "agent.actionGrants"

    private(set) var grants: [Grant]

    private let storage: any AgentGrantStorage

    init(storage: any AgentGrantStorage = UserDefaults.standard) {
        self.storage = storage
        grants = Self.load(from: storage)
    }

    static func normalizedHost(_ host: String?) -> String? {
        guard let host = host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    func isAlwaysAllowed(_ category: SensitiveAction.Category, host: String?) -> Bool {
        guard let host = Self.normalizedHost(host) else { return false }
        return grants.contains { $0.category == category && $0.host == host }
    }

    func allowAlways(_ category: SensitiveAction.Category, host: String?) {
        guard let host = Self.normalizedHost(host) else { return }
        guard !isAlwaysAllowed(category, host: host) else { return }
        grants.append(Grant(host: host, category: category, grantedAt: Date()))
        persist()
    }

    func revoke(_ grant: Grant) {
        grants.removeAll { $0.id == grant.id }
        persist()
    }

    func revokeAll() {
        guard !grants.isEmpty else { return }
        grants.removeAll()
        persist()
    }

    var grantsByHost: [(host: String, categories: [SensitiveAction.Category])] {
        Dictionary(grouping: grants, by: \.host)
            .map { (host: $0.key, categories: $0.value.map(\.category).sorted { $0.rawValue < $1.rawValue }) }
            .sorted { $0.host < $1.host }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(grants) else { return }
        storage.grantData = data
    }

    private static func load(from storage: any AgentGrantStorage) -> [Grant] {
        guard let data = storage.grantData,
              let decoded = try? JSONDecoder().decode([Grant].self, from: data)
        else { return [] }
        return decoded
    }
}

@MainActor
protocol AgentGrantStorage: AnyObject {
    var grantData: Data? { get set }
}

extension UserDefaults: AgentGrantStorage {
    var grantData: Data? {
        get { data(forKey: AgentActionPolicy.storageKey) }
        set { set(newValue, forKey: AgentActionPolicy.storageKey) }
    }
}
