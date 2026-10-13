// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct GitHubClient: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    let transport: Transport

    init(transport: @escaping Transport = Self.send) {
        self.transport = transport
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration, delegate: GitHubRedirectPolicy(), delegateQueue: nil)
    }()

    static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw GitHubFailure.invalidResponse }
        return (data, response)
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func request(
        path: String, token: String, method: String = "GET", body: Data? = nil, headers: [String: String] = [:]
    ) async throws -> (Data, HTTPURLResponse) {
        guard !token.contains(where: { $0.isNewline }), path.hasPrefix("/"),
              let url = URL(string: "https://api.github.com" + path), url.host == "api.github.com" else {
            throw GitHubFailure.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Linen-GitHub", forHTTPHeaderField: "User-Agent")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await transport(request)
        if response.statusCode == 304, headers["If-Modified-Since"] != nil {
            return (data, response)
        }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 {
                throw GitHubFailure.unauthorized
            }
            let error = try? JSONDecoder().decode(APIError.self, from: data)
            if response.statusCode == 429 || response.statusCode == 403 {
                let retry = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
                let exhausted = response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0"
                let reset = exhausted ? response.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(Double.init) : nil
                let secondary = error?.message.localizedCaseInsensitiveContains("rate limit") == true
                if retry != nil || exhausted || response.statusCode == 429 || secondary {
                    let until = retry.map { Date.now.addingTimeInterval(max(60, $0)) }
                        ?? reset.map(Date.init(timeIntervalSince1970:)) ?? Date.now.addingTimeInterval(60)
                    throw GitHubFailure.rateLimited(max(until, Date.now.addingTimeInterval(60)))
                }
            }
            let message = error?.message ?? String(localized: "GitHub request failed (\(response.statusCode)).")
            throw GitHubFailure.api(String(message.prefix(500)))
        }
        return (data, response)
    }

    private static func checkRateLimit(_ errors: [APIError]?, _ response: HTTPURLResponse) throws {
        guard errors?.contains(where: { $0.type == "RATE_LIMITED" }) == true else { return }
        let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(Double.init)
        throw GitHubFailure.rateLimited(reset.map(Date.init(timeIntervalSince1970:)) ?? .now.addingTimeInterval(60))
    }

    func account(token: String) async throws -> GitHubAccount {
        let (data, _) = try await request(path: "/user", token: token)
        return try Self.decoder().decode(GitHubAccount.self, from: data)
    }

    func pullRequests(query: String, cursor: String? = nil, token: String) async throws -> GitHubPRPage {
        let variables: [String: Any] = ["query": query, "cursor": cursor as Any? ?? NSNull()]
        let body = try JSONSerialization.data(withJSONObject: ["query": Self.search, "variables": variables])
        let (data, response) = try await request(path: "/graphql", token: token, method: "POST", body: body)
        let result = try Self.decoder().decode(SearchEnvelope.self, from: data)
        try Self.checkRateLimit(result.errors, response)
        guard let search = result.data?.search else {
            throw result.errors?.first.map { GitHubFailure.api(String($0.message.prefix(500))) } ?? GitHubFailure.invalidResponse
        }
        return GitHubPRPage(
            items: search.nodes.compactMap { $0 }.filter { $0.reference != nil },
            total: search.issueCount,
            cursor: search.pageInfo.hasNextPage ? search.pageInfo.endCursor : nil
        )
    }

    func matchCount(query: String, token: String) async throws -> Int {
        let body = try JSONSerialization.data(withJSONObject: ["query": Self.count, "variables": ["query": query]])
        let (data, response) = try await request(path: "/graphql", token: token, method: "POST", body: body)
        let result = try Self.decoder().decode(CountEnvelope.self, from: data)
        try Self.checkRateLimit(result.errors, response)
        guard let count = result.data?.search.issueCount else {
            throw result.errors?.first.map { GitHubFailure.api(String($0.message.prefix(500))) } ?? GitHubFailure.invalidResponse
        }
        return count
    }

    func triage(
        login: String, repositories: [String], related: [GitHubPullRequestReference],
        now: Date = .now, token: String
    ) async throws -> GitHubTriage {
        try Self.validate(login: login)
        let variables = Self.triageQueries(login: login, repositories: repositories, now: now)
        let lookups = related.prefix(20).enumerated().map { index, pr in
            "  r\(index): repository(owner: \"\(pr.owner)\", name: \"\(pr.repository)\") { pullRequest(number: \(pr.number)) { ...LinenPR } }"
        }
        let query = Self.triage.replacingOccurrences(of: "  LOOKUPS", with: lookups.joined(separator: "\n"))
        let body = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        let (data, response) = try await request(path: "/graphql", token: token, method: "POST", body: body)
        let result = try Self.decoder().decode(TriageEnvelope.self, from: data)
        try Self.checkRateLimit(result.errors, response)
        guard let nodes = result.data else {
            throw result.errors?.first.map { GitHubFailure.api(String($0.message.prefix(500))) } ?? GitHubFailure.invalidResponse
        }
        let search = { (key: String) in (nodes[key]??.nodes ?? []).compactMap { $0 }.filter { $0.reference != nil } }
        return GitHubTriage(
            reviewRequested: search("review"),
            authored: search("authored"),
            recent: search("recent"),
            related: nodes.compactMap { key, node in key.hasPrefix("r") ? Int(key.dropFirst()).map { ($0, node?.pullRequest) } : nil }
                .sorted { $0.0 < $1.0 }.compactMap(\.1).filter { $0.reference != nil }
        )
    }

    func authoredPullRequests(login: String, token: String) async throws -> [GitHubInboxPR] {
        try Self.validate(login: login)
        return try await pullRequests(query: Self.authoredQuery(login: login), token: token).items
    }

    private static func validate(login: String) throws {
        guard !login.isEmpty, login.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
            throw GitHubFailure.invalidResponse
        }
    }

    static func authoredQuery(login: String) -> String {
        "is:pr is:open archived:false author:\(login) sort:updated-desc"
    }

    static func triageQueries(login: String, repositories: [String], now: Date) -> [String: String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let day = now.addingTimeInterval(-GitHubInboxSection.recentWindow)
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        let date = String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
        let base = "is:pr is:open archived:false created:>=\(date) -author:\(login) sort:created-desc"
        return [
            "review": "is:pr is:open archived:false review-requested:\(login) sort:updated-desc",
            "authored": authoredQuery(login: login),
            "recent": scoped(base, login: login, repositories: repositories),
        ]
    }

    static func scoped(_ base: String, login: String, repositories: [String]) -> String {
        var scope = "user:\(login)"
        var seen: Set<String> = []
        for repository in repositories {
            guard GitHubPaletteRoute.isRepository(repository), seen.insert(repository.lowercased()).inserted else { continue }
            let next = scope + " repo:\(repository)"
            guard base.count + 1 + next.count <= 256 else { break }
            scope = next
        }
        return "\(base) \(scope)"
    }

    static func paletteQueries(_ query: String, login: String, repositories: [String]) -> [String: String] {
        let text = String(query.prefix(120))
        return [
            "scoped": scoped("\(text) archived:false sort:updated-desc", login: login, repositories: repositories),
            "mine": "\(text) involves:\(login) sort:updated-desc",
            "repos": "\(text) in:name",
        ]
    }

    func paletteSearch(_ query: String, login: String, repositories: [String], token: String) async throws -> [GitHubSearchHit] {
        try Self.validate(login: login)
        let variables = Self.paletteQueries(query, login: login, repositories: repositories)
        let body = try JSONSerialization.data(withJSONObject: ["query": Self.palette, "variables": variables])
        let (data, response) = try await request(path: "/graphql", token: token, method: "POST", body: body)
        let result = try Self.decoder().decode(PaletteEnvelope.self, from: data)
        try Self.checkRateLimit(result.errors, response)
        guard let payload = result.data else {
            throw result.errors?.first.map { GitHubFailure.api(String($0.message.prefix(500))) } ?? GitHubFailure.invalidResponse
        }
        var seen: Set<String> = []
        let items = (payload.mine?.values ?? []) + (payload.scoped?.values ?? [])
        let hits = items.compactMap(\.hit) + (payload.repos?.values ?? []).compactMap(\.hit)
        return hits.filter { seen.insert($0.id).inserted }
    }

    func pullRequest(_ reference: GitHubPullRequestReference, token: String) async throws -> GitHubInboxPR {
        let variables: [String: Any] = ["owner": reference.owner, "name": reference.repository, "number": reference.number]
        let body = try JSONSerialization.data(withJSONObject: ["query": Self.single, "variables": variables])
        let (data, response) = try await request(path: "/graphql", token: token, method: "POST", body: body)
        let result = try Self.decoder().decode(SingleEnvelope.self, from: data)
        try Self.checkRateLimit(result.errors, response)
        guard let pr = result.data?.repository?.pullRequest, pr.reference != nil else {
            throw result.errors?.first.map { GitHubFailure.api(String($0.message.prefix(500))) } ?? GitHubFailure.invalidResponse
        }
        return pr
    }

    func pullRequestDetails(
        _ reference: GitHubPullRequestReference, includeTeams: Bool = false, token: String
    ) async throws -> GitHubPRDetails {
        let variables: [String: Any] = ["owner": reference.owner, "name": reference.repository, "number": reference.number]
        let query = Self.details.replacingOccurrences(of: " TEAMS", with: includeTeams ? " ... on Team { name avatarUrl(size: 64) }" : "")
        let body = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        let (data, response) = try await request(path: "/graphql", token: token, method: "POST", body: body)
        let result = try Self.decoder().decode(DetailsEnvelope.self, from: data)
        try Self.checkRateLimit(result.errors, response)
        guard let pr = result.data?.repository?.pullRequest else {
            throw result.errors?.first.map { GitHubFailure.api(String($0.message.prefix(500))) } ?? GitHubFailure.invalidResponse
        }
        return pr.details
    }

    func thread(_ subject: GitHubThreadSubject, token: String) async throws -> GitHubThreadPreview {
        let variables: [String: Any]
        let query: String
        switch (subject.kind, subject.number) {
        case let (.issueOrPullRequest, number?):
            (query, variables) = (Self.thread, ["owner": subject.owner, "name": subject.name, "number": number])
        case let (.discussion, number?):
            (query, variables) = (Self.discussion, ["owner": subject.owner, "name": subject.name, "number": number])
        case (.discussion, nil):
            let title = subject.title.replacingOccurrences(of: "\"", with: " ")
            (query, variables) = (Self.discussionSearch, ["query": "repo:\(subject.owner)/\(subject.name) in:title \"\(title)\""])
        case (.issueOrPullRequest, nil):
            throw GitHubFailure.invalidResponse
        }
        let body = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        let (data, response) = try await request(path: "/graphql", token: token, method: "POST", body: body)
        let result = try Self.decoder().decode(ThreadEnvelope.self, from: data)
        try Self.checkRateLimit(result.errors, response)
        let found = result.data?.repository?.issueOrPullRequest ?? result.data?.repository?.discussion
            ?? result.data?.search?.values.first { $0.title?.caseInsensitiveCompare(subject.title) == .orderedSame }
        guard let preview = found?.preview else {
            throw result.errors?.first.map { GitHubFailure.api(String($0.message.prefix(500))) } ?? GitHubFailure.invalidResponse
        }
        return preview
    }

    func notifications(before: Date? = nil, since lastModified: String? = nil, token: String) async throws -> GitHubNotificationPage {
        let cutoff = before.map { "&before=" + $0.formatted(.iso8601) } ?? ""
        let (data, response) = try await request(
            path: "/notifications?all=false&per_page=50" + cutoff, token: token,
            headers: lastModified.map { ["If-Modified-Since": $0] } ?? [:]
        )
        let interval = Double(response.value(forHTTPHeaderField: "X-Poll-Interval") ?? "") ?? 60
        let pollInterval = interval.isFinite ? max(60, interval) : 60
        if response.statusCode == 304 {
            return GitHubNotificationPage(items: [], hasMore: false, pollInterval: pollInterval, lastModified: lastModified, isUnchanged: true)
        }
        let items = try Self.decoder().decode([GitHubNotification].self, from: data)
        return GitHubNotificationPage(
            items: items.filter(\.unread),
            hasMore: response.value(forHTTPHeaderField: "Link")?.contains("rel=\"next\"") == true,
            pollInterval: pollInterval,
            scopes: response.value(forHTTPHeaderField: "X-OAuth-Scopes").map {
                Set($0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            },
            requiresSSO: response.value(forHTTPHeaderField: "X-GitHub-SSO")?.contains("partial-results") == true,
            lastModified: response.value(forHTTPHeaderField: "Last-Modified")
        )
    }

    func markRead(id: String, token: String) async throws {
        guard !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw GitHubFailure.invalidResponse }
        _ = try await request(path: "/notifications/threads/\(id)", token: token, method: "PATCH")
    }

    private struct APIError: Decodable {
        let message: String
        let type: String?
    }

    private struct SearchEnvelope: Decodable {
        let data: SearchData?
        let errors: [APIError]?
    }

    private struct SearchData: Decodable {
        let search: SearchResult
    }

    private struct CountEnvelope: Decodable {
        struct Count: Decodable { let issueCount: Int }
        struct Payload: Decodable { let search: Count }
        let data: Payload?
        let errors: [APIError]?
    }

    private struct SearchResult: Decodable {
        let nodes: [GitHubInboxPR?]
        let issueCount: Int
        let pageInfo: PageInfo
    }

    private struct TriageEnvelope: Decodable {
        let data: [String: TriageNode?]?
        let errors: [APIError]?
    }

    private struct TriageNode: Decodable {
        let nodes: [GitHubInboxPR?]?
        let pullRequest: GitHubInboxPR?
    }

    private struct SingleEnvelope: Decodable {
        struct Repository: Decodable {
            let pullRequest: GitHubInboxPR?
        }
        struct Payload: Decodable {
            let repository: Repository?
        }
        let data: Payload?
        let errors: [APIError]?
    }

    private struct PaletteEnvelope: Decodable {
        struct Payload: Decodable {
            let scoped: Nodes<RawHit>?
            let mine: Nodes<RawHit>?
            let repos: Nodes<RawRepository>?
        }
        let data: Payload?
        let errors: [APIError]?
    }

    private struct RawLinks: Decodable {
        struct Link: Decodable {
            let url: URL
        }
        let nodes: [Link?]?

        var first: URL? {
            nodes?.compactMap { $0 }.first.flatMap { GitHubClient.webURL($0.url) }
        }
    }

    private struct RawHit: Decodable {
        let hit: GitHubSearchHit?

        private enum Keys: String, CodingKey {
            case kind, number, title, url, issueState, repository, closingIssuesReferences, closedByPullRequestsReferences
        }

        private struct Repository: Decodable {
            let nameWithOwner: String
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            switch try container.decodeIfPresent(String.self, forKey: .kind) {
            case "PullRequest":
                let pr = try GitHubInboxPR(from: decoder)
                let linked = try container.decodeIfPresent(RawLinks.self, forKey: .closingIssuesReferences)?.first
                hit = pr.reference == nil ? nil : GitHubSearchHit(
                    kind: .pullRequest(pr), title: pr.title, number: pr.number,
                    repository: pr.repository.nameWithOwner, url: pr.url, linked: linked
                )
            case "Issue":
                guard let url = GitHubClient.webURL(try container.decode(URL.self, forKey: .url)) else {
                    hit = nil
                    return
                }
                hit = GitHubSearchHit(
                    kind: .issue(state: try container.decode(String.self, forKey: .issueState)),
                    title: try container.decode(String.self, forKey: .title),
                    number: try container.decode(Int.self, forKey: .number),
                    repository: try container.decode(Repository.self, forKey: .repository).nameWithOwner,
                    url: url,
                    linked: try container.decodeIfPresent(RawLinks.self, forKey: .closedByPullRequestsReferences)?.first
                )
            default:
                hit = nil
            }
        }
    }

    private struct RawRepository: Decodable {
        let nameWithOwner: String?
        let description: String?
        let isPrivate: Bool?
        let url: URL?

        var hit: GitHubSearchHit? {
            guard let nameWithOwner, let url = GitHubClient.webURL(url) else { return nil }
            return GitHubSearchHit(
                kind: .repository(description: description, isPrivate: isPrivate ?? false),
                title: nameWithOwner, number: nil, repository: nameWithOwner, url: url
            )
        }
    }

    private struct DetailsEnvelope: Decodable {
        struct Repository: Decodable {
            let pullRequest: RawDetails?
        }
        struct Payload: Decodable {
            let repository: Repository?
        }
        let data: Payload?
        let errors: [APIError]?
    }

    private struct ThreadEnvelope: Decodable {
        struct Repository: Decodable {
            let issueOrPullRequest: RawConversation?
            let discussion: RawConversation?
        }
        struct Payload: Decodable {
            let repository: Repository?
            let search: Nodes<RawConversation>?
        }
        let data: Payload?
        let errors: [APIError]?
    }

    private struct RawConversationPost: Decodable {
        let author: GitHubInboxPR.Author?
        let bodyText: String
        let createdAt: Date
        var replies: Nodes<RawConversationPost>?

        var post: GitHubThreadPreview.Post {
            GitHubThreadPreview.Post(author: author, body: bodyText, createdAt: createdAt)
        }

        var newest: RawConversationPost {
            replies?.values.last ?? self
        }
    }

    private struct RawConversationThread: Decodable {
        let comments: Nodes<RawConversationPost>?
    }

    private struct RawConversation: Decodable {
        let title: String?
        let author: GitHubInboxPR.Author?
        let bodyText: String?
        let createdAt: Date?
        let comments: Nodes<RawConversationPost>?
        let reviews: Nodes<RawConversationPost>?
        let reviewThreads: Nodes<RawConversationThread>?

        var preview: GitHubThreadPreview? {
            guard let bodyText, let createdAt else { return nil }
            let replies = (comments?.values ?? []).map(\.newest)
            let reviewed = (reviews?.values ?? []).filter { !$0.bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let inline = (reviewThreads?.values ?? []).flatMap { $0.comments?.values ?? [] }
            return GitHubThreadPreview(
                opening: GitHubThreadPreview.Post(author: author, body: bodyText, createdAt: createdAt),
                latest: (replies + reviewed + inline).max { $0.createdAt < $1.createdAt }?.post,
                commentCount: comments?.totalCount ?? 0
            )
        }
    }

    private struct Nodes<Node: Decodable>: Decodable {
        let nodes: [Node?]?
        var totalCount: Int?

        var values: [Node] {
            (nodes ?? []).compactMap { $0 }
        }
    }

    private struct RawActor: Decodable {
        let login: String?
        let name: String?
        let kind: String?
        var avatarUrl: URL?

        var actor: GitHubPRDetails.Actor? {
            login.map {
                GitHubPRDetails.Actor(login: $0, isBot: GitHubPRDetails.isBot(login: $0, kind: kind),
                                      avatarURL: GitHubAccount.avatarURL(avatarUrl))
            }
        }
    }

    private struct RawComment: Decodable {
        let author: RawActor?
        let body: String?
        let bodyText: String
        let url: URL?
        let createdAt: Date?

        var comment: GitHubPRDetails.Comment {
            GitHubPRDetails.Comment(author: author?.actor, text: bodyText, markdown: String((body ?? bodyText).prefix(60_000)),
                                    url: GitHubClient.webURL(url), date: createdAt)
        }
    }

    private struct RawThread: Decodable {
        let isResolved: Bool
        let isOutdated: Bool
        let path: String
        let line: Int?
        let comments: Nodes<RawComment>
    }

    private struct RawCheckApp: Decodable {
        let logoUrl: URL?
    }

    private struct RawWorkflowRun: Decodable {
        struct Workflow: Decodable {
            let name: String
        }
        let event: String?
        let workflow: Workflow?
    }

    private struct RawCheck: Decodable {
        struct Suite: Decodable {
            let app: RawCheckApp?
            let workflowRun: RawWorkflowRun?
        }
        let kind: String?
        let name: String?
        var checkSuite: Suite?
        var startedAt: Date?
        var avatarUrl: URL?
        let status: String?
        let conclusion: String?
        let detailsUrl: URL?
        let completedAt: Date?
        let context: String?
        let state: String?
        let targetUrl: URL?
        let createdAt: Date?

        var check: GitHubPRDetails.Check? {
            if kind == "StatusContext", let context {
                let result: GitHubPRDetails.Check.State = switch state {
                case "SUCCESS":
                    .passed
                case "FAILURE", "ERROR":
                    .failed
                default:
                    .pending
                }
                return GitHubPRDetails.Check(name: context, state: result, url: GitHubClient.httpsURL(targetUrl), date: createdAt,
                                             iconURL: GitHubAccount.avatarURL(avatarUrl))
            }
            guard let name else { return nil }
            let result: GitHubPRDetails.Check.State = switch conclusion {
            case "SUCCESS", "NEUTRAL":
                .passed
            case "FAILURE", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE", "CANCELLED":
                .failed
            case "SKIPPED", "STALE":
                .skipped
            default:
                .pending
            }
            return GitHubPRDetails.Check(
                name: name, state: result, url: GitHubClient.httpsURL(detailsUrl), date: completedAt,
                workflow: checkSuite?.workflowRun?.workflow?.name, event: checkSuite?.workflowRun?.event,
                iconURL: GitHubAccount.avatarURL(checkSuite?.app?.logoUrl), startedAt: startedAt
            )
        }
    }

    private struct RawRollup: Decodable {
        let contexts: Nodes<RawCheck>
    }

    private struct RawCommit: Decodable {
        struct Commit: Decodable {
            let statusCheckRollup: RawRollup?
        }
        let commit: Commit
    }

    private struct RawReview: Decodable {
        let state: String
        let author: RawActor?
    }

    private struct RawRequest: Decodable {
        let requestedReviewer: RawActor?
    }

    private struct RawFile: Decodable {
        let path: String
        let additions: Int
        let deletions: Int
    }

    private struct RawIssue: Decodable {
        let number: Int
        let title: String
        let url: URL
    }

    private struct RawDetails: Decodable {
        let body: String
        let updatedAt: Date
        let mergeStateStatus: String?
        let reviewRequests: Nodes<RawRequest>
        let latestOpinionatedReviews: Nodes<RawReview>
        let reviewThreads: Nodes<RawThread>
        let comments: Nodes<RawComment>
        let files: Nodes<RawFile>?
        let closingIssuesReferences: Nodes<RawIssue>?
        let commits: Nodes<RawCommit>

        var details: GitHubPRDetails {
            let checks = (commits.values.last?.commit.statusCheckRollup?.contexts.values ?? []).compactMap(\.check)
            var unique: [String: GitHubPRDetails.Check] = [:]
            for check in checks where unique[check.title].map({ check.state.rawValue < $0.state.rawValue }) ?? true {
                unique[check.title] = check
            }
            let threads = reviewThreads.values.filter { !$0.isResolved }
                .sorted { !$0.isOutdated && $1.isOutdated }
                .compactMap { thread -> GitHubPRDetails.Comment? in
                    guard var comment = thread.comments.values.first?.comment else { return nil }
                    comment.path = thread.path
                    comment.line = thread.line
                    return comment
                }
            return GitHubPRDetails(
                summary: GitHubPRDetails.readable(String(body.prefix(60_000))),
                mergeState: mergeStateStatus,
                checks: unique.values.sorted { ($0.state.rawValue, $0.title) < ($1.state.rawValue, $1.title) },
                reviews: latestOpinionatedReviews.values.compactMap { review in
                    review.author?.actor.map { GitHubPRDetails.Review(author: $0, state: review.state) }
                },
                pendingReviewers: reviewRequests.values.compactMap { request in
                    request.requestedReviewer.flatMap { reviewer in
                        (reviewer.login ?? reviewer.name).map {
                            GitHubPRDetails.Actor(login: $0, isBot: GitHubPRDetails.isBot(login: $0, kind: reviewer.kind),
                                                  avatarURL: GitHubAccount.avatarURL(reviewer.avatarUrl))
                        }
                    }
                },
                hiddenTeams: reviewRequests.values.filter { $0.requestedReviewer?.kind == "Team" && $0.requestedReviewer?.name == nil }.count,
                threads: threads,
                comments: comments.values.map(\.comment).reversed(),
                files: (files?.values ?? []).map { GitHubPRDetails.File(path: $0.path, additions: $0.additions, deletions: $0.deletions) },
                fileCount: files?.totalCount ?? 0,
                issues: (closingIssuesReferences?.values ?? []).compactMap { issue in
                    GitHubClient.webURL(issue.url).map { GitHubPRDetails.Issue(number: issue.number, title: issue.title, url: $0) }
                },
                updatedAt: updatedAt
            )
        }
    }

    static func httpsURL(_ url: URL?) -> URL? {
        guard let url, url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }

    static func webURL(_ url: URL?) -> URL? {
        guard let url = httpsURL(url), url.host == "github.com", url.port == nil || url.port == 443 else { return nil }
        return url
    }

    private struct PageInfo: Decodable {
        let hasNextPage: Bool
        let endCursor: String?
    }

    private static let search = """
    query LinenPullRequests($query: String!, $cursor: String) {
      search(query: $query, type: ISSUE_ADVANCED, first: 50, after: $cursor) {
        issueCount
        pageInfo { hasNextPage endCursor }
        nodes { ...LinenPR }
      }
    }
    \(pullRequestFields)
    """

    private static let count = """
    query LinenMatchCount($query: String!) {
      search(query: $query, type: ISSUE_ADVANCED, first: 1) { issueCount }
    }
    """

    private static let palette = """
    query LinenPaletteSearch($scoped: String!, $mine: String!, $repos: String!) {
      mine: search(query: $mine, type: ISSUE, first: 6) { nodes { ...LinenHit } }
      scoped: search(query: $scoped, type: ISSUE, first: 6) { nodes { ...LinenHit } }
      repos: search(query: $repos, type: REPOSITORY, first: 5) {
        nodes { ... on Repository { nameWithOwner description isPrivate url } }
      }
    }
    fragment LinenHit on SearchResultItem {
      kind: __typename
      ... on PullRequest { ...LinenPR closingIssuesReferences(first: 1) { nodes { url } } }
      ... on Issue {
        number title url issueState: state repository { nameWithOwner }
        closedByPullRequestsReferences(first: 1, includeClosedPrs: true) { nodes { url } }
      }
    }
    \(pullRequestFields)
    """

    private static let single = """
    query LinenPullRequest($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) { pullRequest(number: $number) { ...LinenPR } }
    }
    \(pullRequestFields)
    """

    private static let details = """
    query LinenPullRequestDetails($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          body updatedAt mergeStateStatus
          reviewRequests(first: 20) {
            nodes { requestedReviewer { kind: __typename ... on User { login avatarUrl(size: 64) } ... on Bot { login avatarUrl(size: 64) } ... on Mannequin { login avatarUrl(size: 64) } TEAMS } }
          }
          latestOpinionatedReviews(first: 20) { nodes { state author { kind: __typename login avatarUrl(size: 64) } } }
          reviewThreads(first: 100) {
            nodes { isResolved isOutdated path line comments(first: 1) { nodes { author { kind: __typename login avatarUrl(size: 64) } body bodyText url createdAt } } }
          }
          comments(last: 50) { nodes { author { kind: __typename login avatarUrl(size: 64) } body bodyText url createdAt } }
          files(first: 100) { totalCount nodes { path additions deletions } }
          closingIssuesReferences(first: 5) { nodes { number title url } }
          commits(last: 1) {
            nodes { commit { statusCheckRollup { contexts(first: 100) { nodes {
              kind: __typename
              ... on CheckRun {
                name status conclusion detailsUrl startedAt completedAt
                checkSuite { app { logoUrl(size: 32) } workflowRun { event workflow { name } } }
              }
              ... on StatusContext { context state targetUrl createdAt avatarUrl(size: 32) }
            } } } } }
          }
        }
      }
    }
    """

    private static let triage = """
    query LinenInbox($review: String!, $authored: String!, $recent: String!) {
      review: search(query: $review, type: ISSUE, first: 30) { nodes { ...LinenPR } }
      authored: search(query: $authored, type: ISSUE, first: 50) { nodes { ...LinenPR } }
      recent: search(query: $recent, type: ISSUE, first: 15) { nodes { ...LinenPR } }
      LOOKUPS
    }
    \(pullRequestFields)
    """

    private static let thread = """
    query LinenThread($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        issueOrPullRequest(number: $number) {
          ... on Issue { ...LinenPost comments(last: 1) { totalCount nodes { ...LinenPost } } }
          ... on PullRequest {
            ...LinenPost
            comments(last: 1) { totalCount nodes { ...LinenPost } }
            reviews(last: 3) { nodes { ...LinenPost } }
            reviewThreads(last: 1) { nodes { comments(last: 1) { nodes { ...LinenPost } } } }
          }
        }
      }
    }
    \(postFields)
    """

    private static let discussion = """
    query LinenDiscussion($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) { discussion(number: $number) { ...LinenDiscussion } }
    }
    \(discussionFields)
    """

    private static let discussionSearch = """
    query LinenDiscussionSearch($query: String!) {
      search(query: $query, type: DISCUSSION, first: 5) { nodes { ... on Discussion { ...LinenDiscussion } } }
    }
    \(discussionFields)
    """

    private static let discussionFields = """
    fragment LinenDiscussion on Discussion {
      title ...LinenPost
      comments(last: 1) { totalCount nodes { ...LinenPost replies(last: 1) { nodes { ...LinenPost } } } }
    }
    \(postFields)
    """

    private static let postFields = """
    fragment LinenPost on Comment { author { login avatarUrl(size: 64) } bodyText createdAt }
    """

    private static let pullRequestFields = """
    fragment LinenPR on PullRequest {
      id number title url state isDraft createdAt updatedAt reviewDecision mergeable
      additions deletions changedFiles headRefName baseRefName
      author { login avatarUrl(size: 64) }
      headRepositoryOwner { login }
      labels(first: 6) { nodes { name color } }
      repository { nameWithOwner }
      comments(last: 10) { totalCount nodes { author { login } } }
      commits(last: 1) { nodes { commit { statusCheckRollup { state contexts(first: 1) {
        totalCount checkRunCountsByState { state count } statusContextCountsByState { state count }
      } } } } }
    }
    """
}

private nonisolated final class GitHubRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        // Credentials are sent only to the explicit OAuth and API endpoints.
        completionHandler(nil)
    }
}
