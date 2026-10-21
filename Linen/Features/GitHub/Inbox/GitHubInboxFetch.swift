// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum GitHubRefreshScope {
    case full, filter, background

    static func merged(_ requested: Self, into running: Self?) -> Self? {
        switch (running, requested) {
        case (nil, _):
            requested
        case (_, .background):
            nil
        case (.filter?, .filter):
            .filter
        default:
            .full
        }
    }
}

nonisolated struct GitHubInboxFetch: Sendable {
    struct Results: Sendable {
        let inbox: Result<GitHubNotificationPage, Error>?
        let triage: Result<GitHubTriage, Error>?
        let authored: Result<[GitHubInboxPR], Error>?
        let pullRequests: Result<GitHubPRPage, Error>?
    }

    var filter: GitHubFilter?
    var notificationsModified: String?
    var knownNotifications: [GitHubNotification]
    var knownRepositories: [String]
    var covered: Set<String>
    var wantsNotifications: Bool
    var wantsTriage: Bool
    var wantsAuthored: Bool

    func run(login: String, client: GitHubClient, token: String) async -> Results {
        var inbox: Result<GitHubNotificationPage, Error>?
        if wantsNotifications {
            inbox = await Self.result { try await client.notifications(since: notificationsModified, token: token) }
        }
        let changed = inbox.flatMap { try? $0.get() }.flatMap { $0.isUnchanged ? nil : $0.items }
        let items = changed ?? knownNotifications
        let repositories = items.map(\.repository.fullName) + knownRepositories
        let related = items.compactMap(\.reference).filter { !covered.contains($0.key) }
        async let triageCall: Result<GitHubTriage, Error>? = wantsTriage ? await Self.result {
            try await client.triage(login: login, repositories: repositories, related: related, token: token)
        } : nil
        async let authoredCall: Result<[GitHubInboxPR], Error>? = wantsAuthored ? await Self.result {
            try await client.authoredPullRequests(login: login, token: token)
        } : nil
        var pullRequests: Result<GitHubPRPage, Error>?
        if let filter {
            pullRequests = await Self.result { try await client.pullRequests(query: filter.searchQuery(login: login), token: token) }
        }
        return Results(inbox: inbox, triage: await triageCall, authored: await authoredCall, pullRequests: pullRequests)
    }

    private static func result<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async -> Result<T, Error> {
        do { return .success(try await operation()) } catch { return .failure(error) }
    }
}
