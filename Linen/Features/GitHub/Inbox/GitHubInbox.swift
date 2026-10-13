// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct GitHubTriage: Equatable, Sendable {
    var reviewRequested: [GitHubInboxPR] = []
    var authored: [GitHubInboxPR] = []
    var recent: [GitHubInboxPR] = []
    var related: [GitHubInboxPR] = []

    var all: [GitHubInboxPR] {
        reviewRequested + authored + recent + related
    }
}

nonisolated struct GitHubInboxItem: Identifiable, Equatable, Sendable {
    enum Reason: Equatable, Sendable {
        case reviewRequested, mentioned, assigned, comment, yourPullRequest, checks, approval
        case authored, opened, activity
    }

    let id: String
    let reason: Reason
    let pr: GitHubInboxPR?
    let notification: GitHubNotification?

    var title: String {
        pr?.title ?? notification?.subject.title ?? ""
    }

    var repository: String {
        pr?.repository.nameWithOwner ?? notification?.repository.fullName ?? ""
    }

    var number: Int? {
        pr?.number ?? notification?.reference?.number
    }

    var updatedAt: Date {
        max(pr?.updatedAt ?? .distantPast, notification?.updatedAt ?? .distantPast)
    }

    var isUnread: Bool {
        notification != nil
    }

    var url: URL? {
        pr?.url ?? notification?.browserURL
    }

    var status: GitHubPRStatus? {
        pr.map(GitHubPRStatus.init)
    }

    var showsThread: Bool {
        guard notification?.thread != nil else { return false }
        return pr == nil || [.comment, .mentioned, .yourPullRequest].contains(reason)
    }

    var symbol: String {
        switch reason {
        case .authored:
            status?.symbol ?? "arrow.triangle.pull"
        case .reviewRequested:
            "eye"
        case .mentioned:
            "at"
        case .assigned:
            "person.crop.circle"
        case .comment, .yourPullRequest:
            "bubble.left"
        case .checks:
            "xmark.circle"
        case .approval:
            "hand.raised"
        case .opened:
            "arrow.triangle.pull"
        case .activity:
            notification?.symbol ?? "bell"
        }
    }

    var headline: LocalizedStringResource {
        switch reason {
        case .reviewRequested:
            "Review requested"
        case .mentioned:
            "Mentioned you"
        case .assigned:
            "Assigned to you"
        case .comment:
            "New comment"
        case .yourPullRequest:
            "New activity on your pull request"
        case .checks:
            "Check activity"
        case .approval:
            "Approval requested"
        case .authored:
            status?.label ?? "Open"
        case .opened:
            openedHeadline
        case .activity:
            notification?.reasonLabel ?? "Updated"
        }
    }

    private var openedHeadline: LocalizedStringResource {
        guard let login = pr?.author?.login else { return "Opened" }
        return "Opened by \(login)"
    }
}

nonisolated struct GitHubPRStatus: Sendable {
    enum Tone: Sendable {
        case neutral, success, warning, danger
    }

    let label: LocalizedStringResource
    let symbol: String
    let tone: Tone
    let rank: Int

    init(_ pr: GitHubInboxPR) {
        if pr.mergeable == "CONFLICTING" {
            self.init("Merge conflicts", "exclamationmark.triangle.fill", .warning, 0)
        } else if pr.checks == "FAILURE" || pr.checks == "ERROR" {
            self.init("Checks failed", "xmark.circle.fill", .danger, 0)
        } else if pr.reviewDecision == "CHANGES_REQUESTED" {
            self.init("Changes requested", "exclamationmark.bubble.fill", .warning, 1)
        } else if pr.isDraft {
            self.init("Draft", "pencil.circle", .neutral, 3)
        } else if pr.reviewDecision == "APPROVED" {
            self.init("Approved", "checkmark.circle.fill", .success, 2)
        } else if pr.checks == "PENDING" || pr.checks == "EXPECTED" {
            self.init("Checks running", "clock", .neutral, 3)
        } else if pr.checks == "SUCCESS" {
            self.init("Checks passed", "checkmark.circle", .neutral, 3)
        } else {
            self.init("Needs review", "arrow.triangle.pull", .neutral, 3)
        }
    }

    private init(_ label: LocalizedStringResource, _ symbol: String, _ tone: Tone, _ rank: Int) {
        self.label = label
        self.symbol = symbol
        self.tone = tone
        self.rank = rank
    }
}

nonisolated struct GitHubInboxSection: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case needsYou, authored, recent, other
    }

    let kind: Kind
    let items: [GitHubInboxItem]

    var id: Kind {
        kind
    }

    var title: LocalizedStringResource {
        switch kind {
        case .needsYou:
            "Needs you"
        case .authored:
            "Your pull requests"
        case .recent:
            "Recently opened"
        case .other:
            "Other activity"
        }
    }

    static let recentWindow: TimeInterval = 7 * 24 * 60 * 60

    static func build(
        triage: GitHubTriage, notifications: [GitHubNotification], login: String?, now: Date = .now
    ) -> [Self] {
        let me = login?.lowercased()
        var pullRequests: [String: GitHubInboxPR] = [:]
        for pr in triage.all where pullRequests[pr.key] == nil {
            pullRequests[pr.key] = pr
        }
        let isMine = { (pr: GitHubInboxPR?) in pr?.author?.login.lowercased() == me && me != nil }

        var needsYou: [GitHubInboxItem] = []
        var recent: [GitHubInboxItem] = []
        var other: [GitHubInboxItem] = []
        var claimed = Set<String>()
        for notification in notifications {
            let pr = notification.key.flatMap { pullRequests[$0] }
            let reason: GitHubInboxItem.Reason? = switch notification.reason {
            case "review_requested":
                .reviewRequested
            case "mention", "team_mention":
                .mentioned
            case "assign":
                .assigned
            case "approval_requested":
                .approval
            case "ci_activity":
                .checks
            case "comment", "author":
                isMine(pr) ? .yourPullRequest : .comment
            default:
                nil
            }
            let item = GitHubInboxItem(id: "n-\(notification.id)", reason: reason ?? .activity, pr: pr, notification: notification)
            if reason != nil {
                needsYou.append(item)
                if let key = notification.key {
                    claimed.insert(key)
                }
            } else if let pr, pr.state == "OPEN", !isMine(pr),
                      let created = pr.createdAt, now.timeIntervalSince(created) <= recentWindow {
                recent.append(GitHubInboxItem(id: item.id, reason: .opened, pr: pr, notification: notification))
                claimed.insert(pr.key)
            } else {
                other.append(item)
            }
        }
        for pr in triage.reviewRequested where !claimed.contains(pr.key) {
            needsYou.append(GitHubInboxItem(id: "review-\(pr.id)", reason: .reviewRequested, pr: pr, notification: nil))
            claimed.insert(pr.key)
        }
        needsYou.sort { $0.updatedAt > $1.updatedAt }

        let unread = Dictionary(notifications.compactMap { n in n.key.map { ($0, n) } }, uniquingKeysWith: { first, _ in first })
        let authored = triage.authored
            .map { GitHubInboxItem(id: "mine-\($0.id)", reason: .authored, pr: $0, notification: unread[$0.key]) }
            .sorted {
                let (lhs, rhs) = ($0.status?.rank ?? 3, $1.status?.rank ?? 3)
                return lhs != rhs ? lhs < rhs : $0.updatedAt > $1.updatedAt
            }

        for pr in triage.recent where !claimed.contains(pr.key) && !isMine(pr) {
            recent.append(GitHubInboxItem(id: "new-\(pr.id)", reason: .opened, pr: pr, notification: nil))
            claimed.insert(pr.key)
        }
        recent.sort { ($0.pr?.createdAt ?? .distantPast) > ($1.pr?.createdAt ?? .distantPast) }

        return [
            Self(kind: .needsYou, items: needsYou),
            Self(kind: .authored, items: authored),
            Self(kind: .recent, items: Array(recent.prefix(15))),
            Self(kind: .other, items: other),
        ].filter { !$0.items.isEmpty }
    }
}
