// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct GitHubPRSnapshot: Codable, Equatable, Sendable {
    let checks: String?
    let review: String?
    let comments: Int
    let mergeable: String

    init(_ pr: GitHubInboxPR) {
        checks = pr.checks
        review = pr.reviewDecision
        comments = pr.comments.totalCount
        mergeable = pr.mergeable
    }
}

nonisolated struct GitHubPRUpdate: Equatable, Sendable {
    let pr: GitHubInboxPR
    let events: [String]

    var summary: String {
        events.formatted(.list(type: .and, width: .narrow))
    }

    static func changes(
        previous: [String: GitHubPRSnapshot], authored: [GitHubInboxPR], activity: Set<String>, login: String? = nil
    ) -> [Self] {
        authored.compactMap { pr in
            let old = previous[pr.id]
            let new = GitHubPRSnapshot(pr)
            var events: [String] = []
            if let old {
                if new.review != old.review, new.review == "APPROVED" {
                    events.append(String(localized: "Approved"))
                }
                if new.review != old.review, new.review == "CHANGES_REQUESTED" {
                    events.append(String(localized: "Changes requested"))
                }
                let failed: Set<String?> = ["FAILURE", "ERROR"]
                if failed.contains(new.checks), !failed.contains(old.checks) {
                    events.append(String(localized: "Checks failed"))
                }
                if new.checks == "SUCCESS", old.checks == "PENDING" || old.checks == "EXPECTED" {
                    events.append(String(localized: "Checks passed"))
                }
                let added = pr.comments.added(since: old.comments, excluding: login)
                if added > 0 {
                    events.append(String(localized: "\(added) new comments"))
                }
                if new.mergeable == "CONFLICTING", old.mergeable != "CONFLICTING" {
                    events.append(String(localized: "Merge conflicts"))
                }
            }
            if events.isEmpty, activity.contains(pr.key) {
                events.append(String(localized: "New activity"))
            }
            return events.isEmpty ? nil : Self(pr: pr, events: events)
        }
    }
}
