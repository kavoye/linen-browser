// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct GitHubInboxPages {
    private(set) var pullRequests: [GitHubInboxPR] = []
    private(set) var totalPRs = 0
    private(set) var nextCursor: String?
    private(set) var notifications: [GitHubNotification] = []
    private(set) var hasMoreNotifications = false
    private(set) var generation = 0
    private(set) var notificationsModified: String?
    private var pullRequestPages = 1
    private var firstPagePRs: Set<String> = []
    private var notificationPage = 1
    private var firstPageNotifications: Set<String> = []
    private var readThreadUpdates: [String: Date] = [:]

    var oldestNotification: Date? {
        notifications.map(\.updatedAt).min()
    }

    mutating func resetPullRequests() {
        generation += 1
        pullRequests = []
        nextCursor = nil
        totalPRs = 0
        pullRequestPages = 1
        firstPagePRs = []
    }

    mutating func reset() {
        resetPullRequests()
        notifications = []
        notificationsModified = nil
        notificationPage = 1
        firstPageNotifications = []
        readThreadUpdates = [:]
        hasMoreNotifications = false
    }

    mutating func applyFirstPage(_ page: GitHubPRPage) {
        pullRequests = Self.merge(page.items, into: pullRequests, firstPage: firstPagePRs, keepsMore: pullRequestPages > 1)
        firstPagePRs = Set(page.items.map(\.id))
        totalPRs = page.total
        if pullRequestPages == 1 {
            nextCursor = page.cursor
        }
    }

    mutating func applyFirstPage(_ page: GitHubNotificationPage) {
        guard !page.isUnchanged else { return }
        let unread = page.items.filter { $0.updatedAt > (readThreadUpdates[$0.id] ?? .distantPast) }
        notifications = Self.merge(unread, into: notifications, firstPage: firstPageNotifications, keepsMore: notificationPage > 1)
        firstPageNotifications = Set(page.items.map(\.id))
        if notificationPage == 1 {
            hasMoreNotifications = page.hasMore
        }
        notificationsModified = page.lastModified
    }

    mutating func append(_ page: GitHubPRPage) {
        let ids = Set(pullRequests.map(\.id))
        pullRequests += page.items.filter { !ids.contains($0.id) }
        pullRequestPages += 1
        nextCursor = page.cursor
    }

    mutating func append(_ page: GitHubNotificationPage) {
        let ids = Set(notifications.map(\.id))
        notifications += page.items.filter {
            !ids.contains($0.id) && $0.updatedAt > (readThreadUpdates[$0.id] ?? .distantPast)
        }
        notificationPage += 1
        hasMoreNotifications = page.hasMore
    }

    mutating func markRead(_ notification: GitHubNotification) {
        readThreadUpdates[notification.id] = notification.updatedAt
        notifications.removeAll { $0.id == notification.id && $0.updatedAt <= notification.updatedAt }
    }

    static func merge<Item: Identifiable>(
        _ fresh: [Item], into loaded: [Item], firstPage: Set<Item.ID>, keepsMore: Bool
    ) -> [Item] {
        guard keepsMore else { return fresh }
        let ids = Set(fresh.map(\.id))
        return fresh + loaded.filter { !ids.contains($0.id) && !firstPage.contains($0.id) }
    }
}
