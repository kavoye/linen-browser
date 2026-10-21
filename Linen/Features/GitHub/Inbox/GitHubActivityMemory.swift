// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct GitHubActivityMemory {
    private(set) var notifies: Bool
    private var snapshots: [String: GitHubPRSnapshot]?
    private var activitySince: Date?
    private let defaults: UserDefaults
    private let isPrivate: Bool

    init(defaults: UserDefaults, isPrivate: Bool) {
        self.defaults = defaults
        self.isPrivate = isPrivate
        notifies = isPrivate ? false : defaults.object(forKey: "github.notifiesAboutPullRequests") as? Bool ?? true
        if !isPrivate {
            snapshots = defaults.data(forKey: "github.pullRequestSnapshots")
                .flatMap { try? JSONDecoder().decode([String: GitHubPRSnapshot].self, from: $0) }
            activitySince = defaults.object(forKey: "github.activitySince") as? Date
        }
    }

    mutating func setNotifies(_ value: Bool) {
        guard !isPrivate else { return }
        if value, !notifies {
            forget()
        }
        notifies = value
        defaults.set(value, forKey: "github.notifiesAboutPullRequests")
    }

    mutating func changes(
        authored: [GitHubInboxPR], notifications items: [GitHubNotification], fetchedAt: Date, login: String?
    ) -> [GitHubPRUpdate] {
        guard !isPrivate else { return [] }
        let since = activitySince
        let activity = Set(items.filter { item in
            since.map { item.updatedAt > $0 } ?? false && item.reason != "ci_activity"
        }.compactMap(\.key))
        var updates: [GitHubPRUpdate] = []
        if let snapshots, notifies {
            updates = GitHubPRUpdate.changes(previous: snapshots, authored: authored, activity: activity, login: login)
        }
        let next = Dictionary(authored.map { ($0.id, GitHubPRSnapshot($0)) }, uniquingKeysWith: { first, _ in first })
        snapshots = next
        activitySince = max(since ?? fetchedAt, items.map(\.updatedAt).max() ?? fetchedAt)
        defaults.set(try? JSONEncoder().encode(next), forKey: "github.pullRequestSnapshots")
        defaults.set(activitySince, forKey: "github.activitySince")
        return updates
    }

    mutating func forget() {
        snapshots = nil
        activitySince = nil
        defaults.removeObject(forKey: "github.pullRequestSnapshots")
        defaults.removeObject(forKey: "github.activitySince")
    }
}
