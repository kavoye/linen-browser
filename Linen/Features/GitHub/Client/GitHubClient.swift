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
        let body = try JSONSerialization.data(withJSONObject: ["query": GitHubQuery.search, "variables": variables])
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
        let body = try JSONSerialization.data(withJSONObject: ["query": GitHubQuery.count, "variables": ["query": query]])
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
        let query = GitHubQuery.triage.replacingOccurrences(of: "  LOOKUPS", with: lookups.joined(separator: "\n"))
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
        let body = try JSONSerialization.data(withJSONObject: ["query": GitHubQuery.palette, "variables": variables])
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
        let body = try JSONSerialization.data(withJSONObject: ["query": GitHubQuery.single, "variables": variables])
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
        let query = GitHubQuery.details.replacingOccurrences(of: " TEAMS", with: includeTeams ? " ... on Team { name avatarUrl(size: 64) }" : "")
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
            (query, variables) = (GitHubQuery.thread, ["owner": subject.owner, "name": subject.name, "number": number])
        case let (.discussion, number?):
            (query, variables) = (GitHubQuery.discussion, ["owner": subject.owner, "name": subject.name, "number": number])
        case (.discussion, nil):
            let title = subject.title.replacingOccurrences(of: "\"", with: " ")
            (query, variables) = (GitHubQuery.discussionSearch, ["query": "repo:\(subject.owner)/\(subject.name) in:title \"\(title)\""])
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

    static func httpsURL(_ url: URL?) -> URL? {
        guard let url, url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }

    static func webURL(_ url: URL?) -> URL? {
        guard let url = httpsURL(url), url.host == "github.com", url.port == nil || url.port == 443 else { return nil }
        return url
    }
}
