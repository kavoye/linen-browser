// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct GitHubAccount: Codable, Equatable, Sendable {
    let login: String
    let name: String?
    let avatarUrl: URL?

    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? login : trimmed
    }

    var profileURL: URL? {
        guard !login.isEmpty, login.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return nil }
        return URL(string: "https://github.com/\(login)")
    }

    var avatarURL: URL? {
        Self.avatarURL(avatarUrl)
    }

    static func avatarURL(_ url: URL?) -> URL? {
        guard let url, url.scheme == "https", url.host == "avatars.githubusercontent.com",
              url.user == nil, url.password == nil, url.port == nil || url.port == 443,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = (components.queryItems ?? []).filter { $0.name != "s" } + [URLQueryItem(name: "s", value: "64")]
        return components.url
    }
}

nonisolated struct GitHubFilter: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var query: String
    var symbol: String?

    static let inboxID = "inbox"

    static var inbox: Self {
        Self(id: inboxID, name: String(localized: "Inbox"), query: String(localized: "Needs you, your pull requests, and recently opened"))
    }

    static var defaults: [Self] {
        [
            Self(id: "assigned", name: String(localized: "Assigned to me"), query: "is:open assignee:@me sort:updated-desc"),
            Self(id: "commented", name: String(localized: "Commented by me"), query: "is:open commenter:@me sort:updated-desc"),
            Self(id: "review", name: String(localized: "Review requested"), query: "is:open review-requested:@me sort:updated-desc"),
            Self(id: "authored", name: String(localized: "My pull requests"), query: "is:open author:@me sort:updated-desc"),
            Self(id: "involved", name: String(localized: "Involving me"), query: "is:open involves:@me sort:updated-desc"),
        ]
    }

    func searchQuery(login: String) -> String {
        GitHubFilterQuery(query).searchQuery.replacing(/:@me(?=[\s)]|$)/, with: ":" + login)
    }

    var symbolName: String {
        if let symbol {
            return symbol
        }
        return switch id {
        case Self.inboxID:
            "tray"
        case "assigned":
            "person"
        case "commented":
            "bubble.left"
        case "review":
            "eye"
        case "authored":
            "arrow.up.circle"
        case "involved":
            "person.2"
        default:
            "line.3.horizontal.decrease"
        }
    }

    static let symbolChoices = [
        "line.3.horizontal.decrease", "tray", "person", "person.2", "bubble.left", "eye",
        "arrow.up.circle", "star", "flag", "bookmark", "tag", "ladybug",
        "hammer", "shippingbox", "bolt", "clock", "checkmark.circle", "exclamationmark.triangle",
    ]
}

nonisolated enum GitHubFilterState: String, CaseIterable, Sendable {
    case open, draft, merged, closed, all

    var token: String? {
        switch self {
        case .open:
            "is:open"
        case .draft:
            "draft:true"
        case .merged:
            "is:merged"
        case .closed:
            "is:closed"
        case .all:
            nil
        }
    }
}

nonisolated enum GitHubFilterSort: String, CaseIterable, Sendable {
    case bestMatch, updated, leastUpdated, newest, oldest, comments, reactions, interactions

    var token: String? {
        switch self {
        case .bestMatch:
            nil
        case .updated:
            "sort:updated-desc"
        case .leastUpdated:
            "sort:updated-asc"
        case .newest:
            "sort:created-desc"
        case .oldest:
            "sort:created-asc"
        case .comments:
            "sort:comments-desc"
        case .reactions:
            "sort:reactions-desc"
        case .interactions:
            "sort:interactions-desc"
        }
    }
}

nonisolated struct GitHubFilterQuery: Equatable, Sendable {
    var state: GitHubFilterState
    var sort: GitHubFilterSort
    var qualifiers: String

    init(state: GitHubFilterState, sort: GitHubFilterSort, qualifiers: String) {
        self.state = state
        self.sort = sort
        self.qualifiers = qualifiers
    }

    init(_ query: String) {
        var tokens = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let states = tokens.filter(Self.isState)
        state = states.count == 1 ? GitHubFilterState.allCases.first { $0.token == states[0] } ?? .all : .all
        if states.count == 1 {
            tokens.removeAll { $0 == states[0] }
        }
        let sorts = tokens.filter { $0.hasPrefix("sort:") }
        let known = sorts.count == 1 ? GitHubFilterSort.allCases.first { $0.token == sorts[0] } : nil
        sort = known ?? .bestMatch
        if known != nil {
            tokens.removeAll { $0 == sorts[0] }
        }
        qualifiers = tokens.joined(separator: " ")
    }

    var query: String {
        var tokens = qualifiers.split(whereSeparator: \.isWhitespace).map(String.init)
        if state != .all {
            tokens.removeAll(where: Self.isState)
        }
        if sort != .bestMatch {
            tokens.removeAll { $0.hasPrefix("sort:") }
        }
        return ([state.token] + tokens.map(Optional.some) + [sort.token]).compactMap { $0 }.joined(separator: " ")
    }

    var searchQuery: String {
        let tokens = qualifiers.split(whereSeparator: \.isWhitespace).map(String.init)
        let sorts = sort == .bestMatch ? tokens.filter { $0.hasPrefix("sort:") } : []
        let terms = tokens.filter { !$0.hasPrefix("sort:") }.joined(separator: " ")
        let grouped = tokens.contains("OR") ? "(\(terms))" : terms
        return (["is:pr", state.token, grouped.isEmpty ? nil : grouped] + sorts.map(Optional.some) + [sort.token])
            .compactMap { $0 }.joined(separator: " ")
    }

    private static func isState(_ token: String) -> Bool {
        GitHubFilterState.allCases.contains { $0.token == token }
    }
}

nonisolated struct GitHubInboxPR: Decodable, Equatable, Identifiable, Sendable {
    struct Repository: Decodable, Equatable, Sendable {
        let nameWithOwner: String
    }
    struct Author: Decodable, Equatable, Sendable {
        let login: String
        var avatarUrl: URL?

        var avatarURL: URL? {
            GitHubAccount.avatarURL(avatarUrl)
        }
    }
    struct Comments: Decodable, Equatable, Sendable {
        struct Comment: Decodable, Equatable, Sendable {
            let author: Owner?
        }
        let totalCount: Int
        var nodes: [Comment?]?

        func added(since count: Int, excluding login: String?) -> Int {
            let added = max(0, totalCount - count)
            guard let login else { return added }
            let own = (nodes ?? []).suffix(added).filter { $0?.author?.login.caseInsensitiveCompare(login) == .orderedSame }
            return added - own.count
        }
    }
    struct Owner: Decodable, Equatable, Sendable {
        let login: String
    }
    struct Label: Decodable, Equatable, Hashable, Sendable {
        let name: String
        let color: String

        var rgb: (red: Double, green: Double, blue: Double)? {
            guard color.count == 6, let value = UInt32(color, radix: 16) else { return nil }
            return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
        }

        func ink(dark: Bool) -> (red: Double, green: Double, blue: Double) {
            let base = rgb ?? (0.5, 0.5, 0.5)
            let toward: Double = dark ? 1 : 0
            var mix = 0.0
            var result = base
            while mix <= 1 {
                result = (base.red + (toward - base.red) * mix, base.green + (toward - base.green) * mix,
                          base.blue + (toward - base.blue) * mix)
                let lightness = Self.luminance(result)
                if dark ? lightness >= 0.45 : lightness <= 0.18 {
                    break
                }
                mix += 0.05
            }
            return result
        }

        static func luminance(_ color: (red: Double, green: Double, blue: Double)) -> Double {
            let linear = { (value: Double) in value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
        }
    }
    struct Labels: Decodable, Equatable, Sendable {
        let nodes: [Label?]
    }

    let id: String
    let number: Int
    let title: String
    let url: URL
    let state: String
    let isDraft: Bool
    let author: Author?
    let repository: Repository
    let updatedAt: Date
    let createdAt: Date?
    let reviewDecision: String?
    let mergeable: String
    let additions: Int
    let deletions: Int
    let changedFiles: Int
    let headRefName: String
    let baseRefName: String
    let comments: Comments
    let commits: GitHubCommitConnection
    var headRepositoryOwner: Owner?
    var labels: Labels?

    var labelList: [Label] {
        labels?.nodes.compactMap { $0 } ?? []
    }

    var baseLabel: String {
        "\(repository.nameWithOwner.split(separator: "/").first.map(String.init) ?? ""):\(baseRefName)"
    }

    var headLabel: String {
        headRepositoryOwner.map { "\($0.login):\(headRefName)" } ?? headRefName
    }

    var reference: GitHubPullRequestReference? {
        GitHubPullRequestReference(url: url)
    }

    var key: String {
        "\(repository.nameWithOwner)#\(number)".lowercased()
    }

    var checks: String? {
        commits.nodes.last?.commit.statusCheckRollup?.state
    }

    var checkCounts: (passed: Int, total: Int)? {
        commits.nodes.last?.commit.statusCheckRollup?.counts
    }

    var stateLabel: LocalizedStringResource {
        if isDraft {
            return "Draft"
        }
        switch state {
        case "MERGED":
            return "Merged"
        case "CLOSED":
            return "Closed"
        default:
            return "Open"
        }
    }

    var checksLabel: LocalizedStringResource {
        switch checks {
        case "SUCCESS":
            "Checks passed"
        case "FAILURE", "ERROR":
            "Checks failed"
        case "PENDING", "EXPECTED":
            "Checks running"
        default:
            "No checks"
        }
    }

    var reviewLabel: LocalizedStringResource {
        switch reviewDecision {
        case "APPROVED":
            "Approved"
        case "CHANGES_REQUESTED":
            "Changes requested"
        case "REVIEW_REQUIRED":
            "Review required"
        default:
            "No reviews"
        }
    }
}

nonisolated struct GitHubCommitConnection: Decodable, Equatable, Sendable {
    let nodes: [GitHubCommitNode]
}

nonisolated struct GitHubCommitNode: Decodable, Equatable, Sendable {
    let commit: GitHubCommitStatus
}

nonisolated struct GitHubCommitStatus: Decodable, Equatable, Sendable {
    struct Rollup: Decodable, Equatable, Sendable {
        struct Count: Decodable, Equatable, Sendable {
            let state: String
            let count: Int
        }
        struct Contexts: Decodable, Equatable, Sendable {
            let totalCount: Int
            var checkRunCountsByState: [Count]?
            var statusContextCountsByState: [Count]?
        }
        let state: String
        var contexts: Contexts?

        var counts: (passed: Int, total: Int)? {
            guard let contexts, contexts.totalCount > 0 else { return nil }
            let all = (contexts.checkRunCountsByState ?? []) + (contexts.statusContextCountsByState ?? [])
            let sum = { (states: Set<String>) in all.filter { states.contains($0.state) }.reduce(0) { $0 + $1.count } }
            let total = contexts.totalCount - sum(["SKIPPED", "STALE"])
            return total > 0 ? (sum(["SUCCESS", "NEUTRAL"]), total) : nil
        }
    }
    let statusCheckRollup: Rollup?
}

nonisolated struct GitHubPRPage: Sendable {
    let items: [GitHubInboxPR]
    let total: Int
    let cursor: String?
}

nonisolated struct GitHubNotification: Decodable, Equatable, Identifiable, Sendable {
    struct Subject: Decodable, Equatable, Sendable {
        let title: String
        let url: URL?
        let type: String
    }
    struct Repository: Decodable, Equatable, Sendable {
        let fullName: String
    }
    let id: String
    let unread: Bool
    let reason: String
    let updatedAt: Date
    let subject: Subject
    let repository: Repository

    var browserURL: URL {
        guard GitHubPullRequestReference(url: URL(string: "https://github.com/\(repository.fullName)/pull/1")) != nil else {
            return URL(string: "https://github.com/notifications")!
        }
        var inbox = URLComponents(string: "https://github.com/notifications")!
        inbox.queryItems = [URLQueryItem(name: "query", value: "repo:\(repository.fullName)")]
        let fallback = inbox.url!
        guard let url = subject.url, url.scheme == "https", url.host == "api.github.com",
              url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return fallback }
        let parts = url.path.split(separator: "/")
        guard parts.count == 5, parts[0] == "repos",
              "\(parts[1])/\(parts[2])".caseInsensitiveCompare(repository.fullName) == .orderedSame else { return fallback }
        let number = Int(parts[4])
        let base = "https://github.com/\(repository.fullName)"
        switch (subject.type, String(parts[3])) {
        case ("PullRequest", "pulls") where (number ?? 0) > 0:
            return URL(string: "\(base)/pull/\(number!)")!
        case ("Issue", "issues") where (number ?? 0) > 0:
            return URL(string: "\(base)/issues/\(number!)")!
        case ("Discussion", "discussions") where (number ?? 0) > 0:
            return URL(string: "\(base)/discussions/\(number!)")!
        case ("Release", "releases"):
            return URL(string: "\(base)/releases")!
        case ("Commit", "commits") where !parts[4].isEmpty && parts[4].allSatisfy(\.isHexDigit):
            return URL(string: "\(base)/commit/\(parts[4])")!
        default:
            return fallback
        }
    }

    var symbol: String {
        switch subject.type {
        case "PullRequest":
            "arrow.triangle.pull"
        case "Issue":
            "circle.inset.filled"
        case "Discussion":
            "bubble.left.and.bubble.right"
        case "Release":
            "tag"
        case "Commit":
            "point.3.connected.trianglepath.dotted"
        case "CheckSuite":
            "checkmark.circle"
        default:
            "bell"
        }
    }

    var reference: GitHubPullRequestReference? {
        guard subject.type == "PullRequest", let url = subject.url,
              url.scheme == "https", url.host == "api.github.com", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else { return nil }
        let parts = url.path.split(separator: "/")
        guard parts.count == 5, parts[0] == "repos", parts[3] == "pulls",
              "\(parts[1])/\(parts[2])".caseInsensitiveCompare(repository.fullName) == .orderedSame else { return nil }
        return GitHubPullRequestReference(url: URL(string: "https://github.com/\(repository.fullName)/pull/\(parts[4])"))
    }

    var key: String? {
        reference?.key
    }

    var thread: GitHubThreadSubject? {
        let repo = repository.fullName.split(separator: "/")
        guard repo.count == 2 else { return nil }
        let number = subject.url.flatMap { url -> Int? in
            guard url.scheme == "https", url.host == "api.github.com", url.user == nil, url.password == nil,
                  url.port == nil || url.port == 443 else { return nil }
            let parts = url.path.split(separator: "/")
            guard parts.count == 5, parts[0] == "repos", ["issues", "pulls", "discussions"].contains(parts[3]),
                  "\(parts[1])/\(parts[2])".caseInsensitiveCompare(repository.fullName) == .orderedSame,
                  let number = Int(parts[4]), number > 0 else { return nil }
            return number
        }
        let owner = String(repo[0]), name = String(repo[1])
        switch subject.type {
        case "Issue", "PullRequest":
            return number.map { GitHubThreadSubject(kind: .issueOrPullRequest, owner: owner, name: name, number: $0, title: subject.title) }
        case "Discussion":
            return GitHubThreadSubject(kind: .discussion, owner: owner, name: name, number: number, title: subject.title)
        default:
            return nil
        }
    }

    var reasonLabel: LocalizedStringResource {
        switch reason {
        case "assign":
            "Assigned to you"
        case "review_requested":
            "Review requested"
        case "comment":
            "New comment"
        case "mention", "team_mention":
            "Mentioned you"
        case "author":
            "Your activity"
        case "ci_activity":
            "Check activity"
        default:
            "Updated"
        }
    }
}

nonisolated struct GitHubThreadSubject: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case issueOrPullRequest, discussion
    }

    let kind: Kind
    let owner: String
    let name: String
    let number: Int?
    let title: String
}

nonisolated struct GitHubThreadPreview: Equatable, Sendable {
    struct Post: Equatable, Sendable {
        let author: GitHubInboxPR.Author?
        let body: String
        let createdAt: Date
    }

    let opening: Post
    let latest: Post?
    let commentCount: Int
}

nonisolated enum GitHubThreadLoad: Equatable, Sendable {
    case loading, loaded(GitHubThreadPreview), failed
}

nonisolated struct GitHubNotificationPage: Sendable {
    let items: [GitHubNotification]
    let hasMore: Bool
    let pollInterval: TimeInterval
    var scopes: Set<String>?
    var requiresSSO = false
    var lastModified: String?
    var isUnchanged = false
}

nonisolated enum GitHubFailure: Error, LocalizedError {
    case notConfigured, storage, expired, denied, invalidResponse, unauthorized
    case api(String)
    case rateLimited(Date)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            String(localized: "GitHub sign-in isn’t set up in this build.")
        case .storage:
            String(localized: "Couldn’t save the GitHub connection in your Keychain.")
        case .expired:
            String(localized: "The sign-in code expired. Connect again to get a new code.")
        case .denied:
            String(localized: "GitHub access wasn’t approved.")
        case .invalidResponse:
            String(localized: "GitHub returned an unexpected response.")
        case .unauthorized:
            String(localized: "Your GitHub connection expired or was revoked. Connect again.")
        case .api(let message):
            message
        case .rateLimited(let date):
            String(localized: "GitHub is limiting requests. Linen refreshes again at \(date, format: .dateTime.hour().minute()).")
        }
    }
}
