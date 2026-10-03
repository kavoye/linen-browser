// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct ExternalAppPermission: Codable, Equatable, Identifiable, Sendable {
    let scheme: String
    let bundleIdentifier: String
    let name: String

    var id: String {
        "\(scheme)|\(bundleIdentifier)"
    }
}

@MainActor
final class TabExternalAppPolicy {
    private let store: SitePermissions
    let isPrivate: Bool
    private var sessionGrants: [String: Set<String>] = [:]

    init(store: SitePermissions, isPrivate: Bool = false) {
        self.store = store
        self.isPrivate = isPrivate
    }

    func allows(_ app: ExternalAppPermission, from origin: String) -> Bool {
        guard !origin.isEmpty else { return false }
        return store.externalApps(for: origin).contains { $0.id == app.id }
            || sessionGrants[origin]?.contains(app.id) == true
    }

    func remember(_ app: ExternalAppPermission, from origin: String) {
        guard !origin.isEmpty else { return }
        if isPrivate {
            sessionGrants[origin, default: []].insert(app.id)
        } else {
            store.allowExternalApp(app, for: origin)
        }
    }
}
