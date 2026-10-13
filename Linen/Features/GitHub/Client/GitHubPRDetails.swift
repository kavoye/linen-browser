// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation

nonisolated struct GitHubPRDetails: Equatable, Sendable {
    struct Actor: Equatable, Sendable {
        let login: String
        let isBot: Bool
        var avatarURL: URL?
    }

    struct Check: Equatable, Identifiable, Sendable {
        enum State: Int, Sendable {
            case failed, pending, passed, skipped
        }

        let name: String
        let state: State
        let url: URL?
        let date: Date?
        var workflow: String?
        var event: String?
        var iconURL: URL?
        var startedAt: Date?

        var id: String {
            title
        }

        var title: String {
            let base = workflow.map { "\($0) / \(name)" } ?? name
            return event.map { "\(base) (\($0))" } ?? base
        }

        var duration: TimeInterval? {
            guard let startedAt, let date, state != .pending else { return nil }
            let seconds = date.timeIntervalSince(startedAt)
            return seconds >= 0 ? seconds : nil
        }
    }

    struct Review: Equatable, Sendable {
        let author: Actor
        let state: String
    }

    struct Comment: Equatable, Identifiable, Sendable {
        let author: Actor?
        let text: String
        var markdown = ""
        let url: URL?
        let date: Date?
        var path: String?
        var line: Int?

        var id: String {
            url?.absoluteString ?? "\(author?.login ?? "")-\(date?.timeIntervalSince1970 ?? 0)-\(text.prefix(40))"
        }

        var isBot: Bool {
            author?.isBot ?? false
        }
    }

    struct File: Equatable, Identifiable, Sendable {
        let path: String
        let additions: Int
        let deletions: Int

        var id: String {
            path
        }

        var churn: Int {
            additions + deletions
        }

        var name: String {
            path.split(separator: "/").last.map(String.init) ?? path
        }

        var anchor: String {
            "diff-" + SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        }
    }

    struct Issue: Equatable, Identifiable, Sendable {
        let number: Int
        let title: String
        let url: URL

        var id: Int {
            number
        }
    }

    let summary: String
    let mergeState: String?
    let checks: [Check]
    let reviews: [Review]
    let pendingReviewers: [Actor]
    var hiddenTeams = 0
    let threads: [Comment]
    let comments: [Comment]
    let files: [File]
    let fileCount: Int
    let issues: [Issue]
    let updatedAt: Date

    static func readable(_ markdown: String) -> String {
        let tags = "details|summary|p|div|span|sub|sup|img|a|b|i|em|strong|picture|source|table|thead|tbody|tr|td|th|kbd|br|hr|h[1-6]|ul|ol|li|blockquote|code|pre"
        let rules: [(String, String)] = [
            ("(?s)<!--.*?-->", ""),
            ("(?is)<summary[^>]*>(.*?)</summary>", "\n**$1**\n"),
            ("(?i)<br\\s*/?>", "\n"),
            ("(?i)</?(?:\(tags))\\b[^>]*>", ""),
            ("!\\[[^\\]]*\\]\\([^)]*\\)", ""),
            ("(?m)^\\s*[-*+] \\[ \\]", "☐"),
            ("(?m)^\\s*[-*+] \\[[xX]\\]", "☑"),
            ("\n{3,}", "\n\n"),
        ]
        var text = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        for (pattern, template) in rules {
            text = text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isBot(login: String, kind: String?) -> Bool {
        kind == "Bot" || login.lowercased().hasSuffix("[bot]")
    }
}

nonisolated struct GitHubPRDigest: Sendable {
    typealias Tone = GitHubPRStatus.Tone

    enum Kind: Sendable {
        case checks, review, threads, comments, conflicts, base
    }

    struct Row: Identifiable, Sendable {
        let kind: Kind
        let tone: Tone
        let title: LocalizedStringResource
        var detail: String?
        var expandable = false
        var icon: String?

        var id: Kind {
            kind
        }

        var symbol: String {
            if let icon {
                return icon
            }
            return switch tone {
            case .success:
                "checkmark.circle.fill"
            case .danger:
                "xmark.circle.fill"
            case .warning:
                "exclamationmark.circle.fill"
            case .neutral:
                kind == .comments ? "bubble.left" : "circle.dashed"
            }
        }
    }

    let verdict: LocalizedStringResource?
    let tone: Tone
    let rows: [Row]

    init(pr: GitHubInboxPR, details: GitHubPRDetails?) {
        let threads = details?.threads.count ?? 0
        (verdict, tone) = Self.verdict(pr: pr, details: details, threads: threads)

        var rows: [Row] = []
        if let details {
            rows.append(Self.reviewRow(pr: pr, details: details))
            rows.append(Self.checksRow(details.checks))
            if threads == 0 {
                rows.append(Row(kind: .threads, tone: .success, title: "No open threads"))
            } else {
                rows.append(Row(kind: .threads, tone: .warning, title: "\(threads) open threads", expandable: true))
            }

            let people = details.comments.filter { !$0.isBot }.count
            if details.comments.isEmpty {
                rows.append(Row(kind: .comments, tone: .neutral, title: "No comments"))
            } else {
                rows.append(Row(kind: .comments, tone: .neutral, title: "\(people) comments", expandable: true))
            }
        }
        if pr.state == "OPEN" {
            rows += Self.mergeRows(pr: pr, mergeState: details?.mergeState)
        }
        self.rows = rows
    }

    private static func verdict(
        pr: GitHubInboxPR, details: GitHubPRDetails?, threads: Int
    ) -> (LocalizedStringResource?, Tone) {
        let failing = (details?.checks ?? []).contains { $0.state == .failed }
        let running = details.map { $0.checks.contains { $0.state == .pending } } ?? (pr.checks == "PENDING" || pr.checks == "EXPECTED")
        let rollupFailed = pr.checks == "FAILURE" || pr.checks == "ERROR"
        if pr.state == "MERGED" {
            return ("Merged", .success)
        } else if pr.state == "CLOSED" {
            return ("Closed", .neutral)
        } else if pr.mergeable == "CONFLICTING" {
            return ("Merge conflicts", .danger)
        } else if failing || rollupFailed {
            return ("Checks failed", .danger)
        } else if pr.reviewDecision == "CHANGES_REQUESTED" {
            return ("Changes requested", .warning)
        } else if pr.isDraft {
            return (nil, .neutral)
        } else if pr.reviewDecision == "REVIEW_REQUIRED" {
            return ("Review required", .warning)
        } else if running {
            return ("Checks running", .neutral)
        } else if threads > 0 {
            return ("\(threads) open threads", .warning)
        } else if details?.mergeState == "BLOCKED" {
            return ("Blocked", .danger)
        }
        return ("Ready to merge", .success)
    }

    private static func reviewRow(pr: GitHubInboxPR, details: GitHubPRDetails) -> Row {
        let reviews = details.reviews
        let approvers = reviews.filter { $0.state == "APPROVED" }.map(\.author.login)
        let blockers = reviews.filter { $0.state == "CHANGES_REQUESTED" }.map(\.author.login)
        let names = { (logins: [String]) in logins.formatted(.list(type: .and)) }
        let reviewExpands = !reviews.isEmpty || !details.pendingReviewers.isEmpty || details.hiddenTeams > 0
        if !blockers.isEmpty {
            return Row(kind: .review, tone: .danger, title: "Changes requested by \(names(blockers))", expandable: true)
        } else if pr.reviewDecision == "REVIEW_REQUIRED" {
            let detail = approvers.isEmpty
                ? String(localized: "Needs an approving review.")
                : String(localized: "Approved by \(names(approvers)). Needs more approvals.")
            return Row(kind: .review, tone: .warning, title: "Review required", detail: detail,
                       expandable: reviewExpands, icon: "minus.circle.fill")
        } else if !approvers.isEmpty {
            return Row(kind: .review, tone: .success, title: "Approved by \(names(approvers))", expandable: true)
        } else if !details.pendingReviewers.isEmpty {
            return Row(kind: .review, tone: .neutral, title: "Waiting on \(names(details.pendingReviewers.map(\.login)))", expandable: true)
        } else if details.hiddenTeams > 0 {
            return Row(kind: .review, tone: .neutral, title: "Waiting on a team", expandable: true)
        }
        return Row(kind: .review, tone: .neutral, title: "No reviews yet", expandable: reviewExpands)
    }

    private static func checksRow(_ checks: [GitHubPRDetails.Check]) -> Row {
        let count = { (state: GitHubPRDetails.Check.State) in checks.filter { $0.state == state }.count }
        let (failed, pending, passed, skipped) = (count(.failed), count(.pending), count(.passed), count(.skipped))
        var parts: [String] = []
        if failed > 0 {
            parts.append(String(localized: "\(failed) failing"))
        }
        if pending > 0 {
            parts.append(String(localized: "\(pending) in progress"))
        }
        if passed > 0 {
            parts.append(failed + pending == 0 ? String(localized: "\(passed) successful checks") : String(localized: "\(passed) successful"))
        }
        if skipped > 0 {
            parts.append(String(localized: "\(skipped) skipped"))
        }
        let summary = parts.formatted(.list(type: .and, width: .narrow))
        if checks.isEmpty {
            return Row(kind: .checks, tone: .neutral, title: "No checks")
        } else if failed > 0 {
            return Row(kind: .checks, tone: .danger, title: "Checks failed", detail: summary, expandable: true)
        } else if pending > 0 {
            return Row(kind: .checks, tone: .warning, title: "Checks running", detail: summary,
                       expandable: true, icon: "clock.fill")
        }
        return Row(kind: .checks, tone: .success, title: "Checks passed", detail: summary, expandable: true)
    }

    private static func mergeRows(pr: GitHubInboxPR, mergeState: String?) -> [Row] {
        var rows: [Row] = []
        if pr.mergeable == "CONFLICTING" {
            rows.append(Row(kind: .conflicts, tone: .danger, title: "Merge conflicts"))
        } else if pr.mergeable == "MERGEABLE" {
            rows.append(Row(kind: .conflicts, tone: .success, title: "No conflicts"))
        }
        if mergeState == "BEHIND" {
            rows.append(Row(kind: .base, tone: .warning, title: "Behind \(pr.baseRefName)"))
        } else if mergeState != nil, mergeState != "UNKNOWN" {
            rows.append(Row(kind: .base, tone: .success, title: "Up to date with \(pr.baseRefName)"))
        }
        return rows
    }
}
