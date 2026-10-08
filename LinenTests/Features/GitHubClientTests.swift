// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Synchronization
import Testing

@testable import Linen

@MainActor
struct GitHubClientTests {
    @Test func aFailedImageIsNotFetchedAgainUntilItsRetryTime() async {
        let fetches = GitHubRequestLog()
        let cache = GitHubImageCache { url in
            fetches.append("image", URLRequest(url: url))
            return (Data(), HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        }
        var date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        cache.now = { date }
        let avatar = URL(string: "https://avatars.githubusercontent.com/u/1?s=64")!

        #expect(await cache.image(for: avatar) == nil)
        #expect(await cache.image(for: avatar) == nil)
        #expect(fetches.count("image") == 1)

        date += 301
        #expect(await cache.image(for: avatar) == nil)
        #expect(fetches.count("image") == 2)
    }

    @Test func accountIncludesNameAvatarAndProfileLink() async throws {
        let client = GitHubClient { request in
            Self.response(#"{"login":"octocat","name":"Octo Cat","avatar_url":"https://avatars.githubusercontent.com/u/1?v=4"}"#, request: request)
        }
        let account = try await client.account(token: "fixture")
        #expect(account.displayName == "Octo Cat")
        #expect(account.profileURL?.absoluteString == "https://github.com/octocat")
        #expect(account.avatarURL?.host == "avatars.githubusercontent.com")
        #expect(URLComponents(url: try #require(account.avatarURL), resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "s", value: "64")) == true)
        let fallback = try GitHubClient.decoder().decode(GitHubAccount.self, from: Data(#"{"login":"octocat","name":"  "}"#.utf8))
        #expect(fallback.displayName == "octocat")
        #expect(fallback.avatarURL == nil)
        let invalid = try GitHubClient.decoder().decode(GitHubAccount.self, from: Data(#"{"login":"../settings","avatar_url":"http://evil.test/image"}"#.utf8))
        #expect(invalid.profileURL == nil)
        #expect(invalid.avatarURL == nil)
    }

    @Test func graphQLProvidesStatusesAndPaginationWithoutPageContent() async throws {
        let client = GitHubClient { request in
            #expect(request.url?.absoluteString == "https://api.github.com/graphql")
            #expect(request.httpMethod == "POST")
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
            let variables = body?["variables"] as? [String: Any]
            #expect(variables?["query"] as? String == "is:pr assignee:octocat")
            #expect(variables?["cursor"] as? String == "next-page")
            return Self.response(Self.search, request: request)
        }
        let page = try await client.pullRequests(query: "is:pr assignee:octocat", cursor: "next-page", token: "test")
        let pr = try #require(page.items.first)
        #expect(pr.reference?.repositoryName == "kavoye/linen-browser")
        #expect(pr.reviewDecision == "CHANGES_REQUESTED")
        #expect(pr.checks == "FAILURE")
        #expect(pr.mergeable == "CONFLICTING")
        #expect(pr.comments.totalCount == 4)
        #expect(page.cursor == "next")
        #expect(page.total == 51)
    }

    @Test func filterSearchesUseAdvancedSearch() async throws {
        let client = GitHubClient { request in
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
            let query = body?["query"] as? String ?? ""
            #expect(query.contains("type: ISSUE_ADVANCED"))
            if query.contains("LinenMatchCount") {
                #expect((body?["variables"] as? [String: Any])?["query"] as? String == "is:pr (label:a OR label:b)")
                return Self.response(#"{"data":{"search":{"issueCount":12}}}"#, request: request)
            }
            return Self.response(Self.search, request: request)
        }
        _ = try await client.pullRequests(query: "is:pr", token: "test")
        #expect(try await client.matchCount(query: "is:pr (label:a OR label:b)", token: "test") == 12)
    }

    @Test func filterSearchesKeepResultsThatAPartialErrorLeft() async throws {
        let forbidden = #"[{"type":"FORBIDDEN","message":"Resource protected by organization SAML enforcement."}]"#
        let pr = GitHubFixtures.pullRequestJSON(state: "OPEN", checks: "SUCCESS", review: nil)
        let client = GitHubClient { request in
            let query = (try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])?["query"] as? String ?? ""
            let json = query.contains("LinenMatchCount")
                ? #"{"data":{"search":{"issueCount":2}},"errors":\#(forbidden)}"#
                : #"{"data":{"search":{"issueCount":2,"nodes":[\#(pr),null],"pageInfo":{"hasNextPage":false,"endCursor":null}}},"errors":\#(forbidden)}"#
            return Self.response(json, request: request)
        }
        #expect(try await client.pullRequests(query: "is:pr involves:octocat", token: "test").items.map(\.number) == [42])
        #expect(try await client.matchCount(query: "is:pr involves:octocat", token: "test") == 2)
        let failing = GitHubClient { request in Self.response(#"{"errors":\#(forbidden)}"#, request: request) }
        await #expect(throws: GitHubFailure.self) { try await failing.pullRequests(query: "is:pr", token: "test") }
    }

    @Test func notificationsUseTheirOwnPollingIntervalAndValidateDestinations() async throws {
        let client = GitHubClient { request in
            Self.response(Self.notifications, request: request, headers: ["X-Poll-Interval": "90", "Link": "<https://api.github.com/notifications?page=2>; rel=\"next\""])
        }
        let page = try await client.notifications(token: "test")
        #expect(page.items.count == 1)
        #expect(page.items.first?.reference?.number == 2)
        #expect(page.hasMore)
        #expect(page.pollInterval == 90)
        let spoofed = Self.notifications.replacingOccurrences(of: "api.github.com/repos", with: "evil.test/repos")
        let values = try GitHubClient.decoder().decode([GitHubNotification].self, from: Data(spoofed.utf8))
        #expect(values.allSatisfy { $0.reference == nil })
    }

    @Test func notificationReadActionUsesOnlyTheThreadEndpoint() async throws {
        let client = GitHubClient { request in
            #expect(request.httpMethod == "PATCH")
            #expect(request.url?.absoluteString == "https://api.github.com/notifications/threads/123")
            return Self.response("", request: request, status: 205)
        }
        try await client.markRead(id: "123", token: "test")
        await #expect(throws: GitHubFailure.self) { try await client.markRead(id: "../user", token: "test") }
    }

    @Test func inboxIncludesDiscussionsIssuesAndOtherActivity() async throws {
        for (type, path, webPath) in [("Discussion", "discussions", "discussions"), ("Issue", "issues", "issues"), ("PullRequest", "pulls", "pull")] {
            let fixture = Self.notifications.replacingOccurrences(of: "PullRequest", with: type)
                .replacingOccurrences(of: "/pulls/2", with: "/\(path)/2")
            let client = GitHubClient { request in
                Self.response(fixture, request: request, headers: ["X-OAuth-Scopes": "read:user, notifications", "X-GitHub-SSO": "partial-results; organizations=123"])
            }
            let page = try await client.notifications(token: "test")
            #expect(page.items.count == 1)
            #expect(page.items.first?.browserURL.absoluteString == "https://github.com/kavoye/linen-browser/\(webPath)/2")
            #expect(page.scopes == ["read:user", "notifications"])
            #expect(page.requiresSSO)
        }
        let fixture = Self.notifications.replacingOccurrences(of: "PullRequest", with: "CheckSuite")
            .replacingOccurrences(of: "https://api.github.com/repos/kavoye/linen-browser/pulls/2", with: "https://evil.test/steal")
        let client = GitHubClient { request in Self.response(fixture, request: request) }
        let page = try await client.notifications(token: "test")
        #expect(page.items.count == 1)
        #expect(page.items.first?.browserURL.host == "github.com")
        #expect(page.items.first?.browserURL.path == "/notifications")
    }

    @Test func notificationsAskOnlyForChangesSinceTheLastPoll() async throws {
        let stamp = "Mon, 05 Oct 2026 12:00:00 GMT"
        let client = GitHubClient { request in
            if let since = request.value(forHTTPHeaderField: "If-Modified-Since") {
                #expect(since == stamp)
                return Self.response("", request: request, status: 304, headers: ["X-Poll-Interval": "120"])
            }
            return Self.response(Self.notifications, request: request, headers: ["Last-Modified": stamp])
        }
        let first = try await client.notifications(token: "test")
        #expect(first.lastModified == stamp)
        #expect(!first.isUnchanged)
        let second = try await client.notifications(since: first.lastModified, token: "test")
        #expect(second.isUnchanged)
        #expect(second.pollInterval == 120)
        let unasked = GitHubClient { Self.response("", request: $0, status: 304) }
        await #expect(throws: GitHubFailure.self) { try await unasked.notifications(token: "test") }
    }

    @Test func relatedPullRequestsKeepNotificationOrder() async throws {
        let references = (1...12).compactMap { GitHubPullRequestReference(url: URL(string: "https://github.com/kavoye/linen-browser/pull/\($0)")) }
        let client = GitHubClient { request in
            let lookups = (0..<12).map { index in
                let pr = Self.pullRequest.replacingOccurrences(of: #""number":2"#, with: #""number":\#(index + 1)"#)
                    .replacingOccurrences(of: "/pull/2", with: "/pull/\(index + 1)")
                return "\"r\(index)\":{\"pullRequest\":\(pr)}"
            }
            let json = #"{"data":{"review":{"nodes":[]},"authored":{"nodes":[]},"recent":{"nodes":[]},"# + lookups.joined(separator: ",") + "}}"
            return Self.response(json, request: request)
        }
        let triage = try await client.triage(login: "octocat", repositories: [], related: references, token: "test")
        #expect(triage.related.map(\.number) == Array(1...12))
    }

    @Test func secondaryRateLimitBacksOffWithoutWaitingForThePrimaryReset() async throws {
        let reset = String(Int(Date.now.timeIntervalSince1970) + 3600)
        let client = GitHubClient { request in
            Self.response(#"{"message":"You have exceeded a secondary rate limit."}"#, request: request, status: 403,
                          headers: ["X-RateLimit-Remaining": "4000", "X-RateLimit-Reset": reset])
        }
        do {
            _ = try await client.account(token: "test")
            Issue.record("Expected rate limit")
        } catch GitHubFailure.rateLimited(let until) {
            #expect(until.timeIntervalSinceNow < 120)
        }
    }

    @Test func graphQLRateLimitBacksOffEvenWithHTTP200() async throws {
        let client = GitHubClient { request in
            Self.response(#"{"errors":[{"message":"Rate limit exceeded","type":"RATE_LIMITED"}]}"#, request: request)
        }
        do {
            _ = try await client.pullRequests(query: "is:pr", token: "test")
            Issue.record("Expected backoff")
        } catch GitHubFailure.rateLimited(let until) {
            #expect(until > .now)
        }
    }

    @Test func notificationReadDoesNotReturnAfterAStaleRefresh() async throws {
        let box = GitHubTestCredentials()
        let latestNotifications = Mutex(Self.notifications)
        let id = UUID()
        try GitHubConnectionStore(profileID: id, storage: box.storage).save("test")
        let client = GitHubClient { request in
            switch request.url!.path {
            case "/user":
                Self.response(#"{"login":"octocat"}"#, request: request)
            case "/graphql":
                Self.response(Self.triage, request: request)
            case "/notifications/threads/123":
                Self.response("", request: request, status: 205)
            default:
                Self.response(latestNotifications.withLock { $0 }, request: request)
            }
        }
        let model = GitHubPanelModel(profileID: id, defaults: UserDefaults(suiteName: TestDefaults.name("GitHubClientTests"))!, client: client, storage: box.storage)
        model.panelDidAppear()
        model.start()
        #expect(await waitUntil { model.lastUpdated != nil })
        let notification = try #require(model.notifications.first)
        model.markRead(notification)
        #expect(await waitUntil { model.notifications.isEmpty && model.markingRead.isEmpty })
        let previous = model.lastUpdated
        model.refresh()
        #expect(await waitUntil { model.lastUpdated != previous })
        #expect(model.notifications.isEmpty)
        #expect(model.triage.reviewRequested.first?.checks == "FAILURE")
        #expect(model.sections.first?.items.first?.isUnread == false)
        latestNotifications.withLock { $0 = Self.notifications.replacingOccurrences(of: "12:00:00Z", with: "12:01:00Z") }
        let lastRefresh = model.lastUpdated
        model.refresh()
        #expect(await waitUntil { model.lastUpdated != lastRefresh })
        #expect(model.notifications.first?.id == notification.id)
        #expect(try #require(model.notifications.first).updatedAt > notification.updatedAt)
        model.disconnect()
    }

    @Test func revokedConnectionRequiresAuthorizationAgain() async throws {
        let box = GitHubTestCredentials()
        let id = UUID()
        try GitHubConnectionStore(profileID: id, storage: box.storage).save("test")
        let client = GitHubClient { request in Self.response("{}", request: request, status: 401) }
        let model = GitHubPanelModel(profileID: id, defaults: UserDefaults(suiteName: TestDefaults.name("GitHub401"))!, client: client, storage: box.storage)
        model.start()
        #expect(await waitUntil { model.needsReconnect })
        #expect(model.lastUpdated == nil)
        #expect(model.errorMessage != nil)
        model.disconnect()
    }

    @Test func threadPreviewPicksTheNewestCommentAcrossReviews() async throws {
        let client = GitHubClient { request in
            let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            let variables = body?["variables"] as? [String: Any]
            #expect((body?["query"] as? String)?.contains("issueOrPullRequest") == true)
            #expect(variables?["number"] as? Int == 4)
            return Self.response(#"""
            {"data":{"repository":{"issueOrPullRequest":{
              "author":{"login":"mira"},"bodyText":"Opening post","createdAt":"2026-10-01T09:00:00Z",
              "comments":{"totalCount":3,"nodes":[{"author":{"login":"alex"},"bodyText":"Older","createdAt":"2026-10-02T09:00:00Z"}]},
              "reviews":{"nodes":[{"author":{"login":"sam"},"bodyText":"","createdAt":"2026-10-04T09:00:00Z"}]},
              "reviewThreads":{"nodes":[{"comments":{"nodes":[{"author":null,"bodyText":"Inline","createdAt":"2026-10-03T09:00:00Z"}]}}]}
            }}}}
            """#, request: request)
        }
        let subject = GitHubThreadSubject(kind: .issueOrPullRequest, owner: "kavoye", name: "linen-browser", number: 4, title: "Fix")
        let thread = try await client.thread(subject, token: "test")
        #expect(thread.opening.body == "Opening post")
        #expect(thread.latest?.body == "Inline")
        #expect(thread.latest?.author == nil)
        #expect(thread.commentCount == 3)
    }

    @Test func discussionWithoutANumberIsFoundByItsExactTitle() async throws {
        let client = GitHubClient { request in
            let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            let variables = body?["variables"] as? [String: Any]
            #expect(variables?["query"] as? String == #"repo:community/community in:title " Files Changed  feedback""#)
            return Self.response(#"""
            {"data":{"search":{"nodes":[
              {"title":"Other","author":{"login":"x"},"bodyText":"No","createdAt":"2026-10-01T09:00:00Z"},
              {},
              {"title":"\"Files Changed\" feedback","author":{"login":"mira"},"bodyText":"Tell us","createdAt":"2026-10-01T09:00:00Z",
               "comments":{"totalCount":38,"nodes":[{"author":{"login":"alex"},"bodyText":"Top","createdAt":"2026-10-02T09:00:00Z",
                 "replies":{"nodes":[{"author":{"login":"octocat"},"bodyText":"Reply","createdAt":"2026-10-03T09:00:00Z"}]}}]}}
            ]}}}
            """#, request: request)
        }
        let subject = GitHubThreadSubject(kind: .discussion, owner: "community", name: "community", number: nil, title: #""Files Changed" feedback"#)
        let thread = try await client.thread(subject, token: "test")
        #expect(thread.latest?.body == "Reply")
        #expect(thread.latest?.author?.login == "octocat")
        #expect(thread.commentCount == 38)
    }

    private nonisolated static func response(
        _ json: String, request: URLRequest, status: Int = 200, headers: [String: String] = [:]
    ) -> (Data, HTTPURLResponse) {
        (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
    }

    private nonisolated static let search = #"""
    {"data":{"search":{"issueCount":51,"pageInfo":{"hasNextPage":true,"endCursor":"next"},"nodes":[{
      "id":"PR_2","number":2,"title":"Fix resizing","url":"https://github.com/kavoye/linen-browser/pull/2",
      "state":"OPEN","isDraft":false,"updatedAt":"2026-10-05T12:00:00Z","reviewDecision":"CHANGES_REQUESTED",
      "mergeable":"CONFLICTING","additions":24,"deletions":8,"changedFiles":3,"headRefName":"fix","baseRefName":"main",
      "author":{"login":"octocat"},"repository":{"nameWithOwner":"kavoye/linen-browser"},"comments":{"totalCount":4},
      "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"FAILURE"}}}]}
    }]}}}
    """#

    @Test func triageScopesRecentSearchAndLooksUpNotifiedPullRequests() async throws {
        let now = try Date("2026-10-06T12:00:00Z", strategy: .iso8601)
        let repositories = ["kavoye/linen-browser", "KAVOYE/linen-browser", "bad repo/x", "../x"]
            + (0..<20).map { "organisation-\($0)/repository-with-a-long-name" }
        let queries = GitHubClient.triageQueries(login: "octocat", repositories: repositories, now: now)
        let recent = try #require(queries["recent"])
        #expect(recent.hasPrefix("is:pr is:open archived:false created:>=2026-09-29 -author:octocat sort:created-desc user:octocat repo:kavoye/linen-browser"))
        #expect(recent.count <= 256)
        #expect(recent.components(separatedBy: "linen-browser").count == 2)
        #expect(!recent.contains("bad repo") && !recent.contains(".."))
        #expect(queries["review"] == "is:pr is:open archived:false review-requested:octocat sort:updated-desc")

        let client = GitHubClient { request in
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
            let query = try #require(body?["query"] as? String)
            #expect(query.contains(#"r0: repository(owner: "kavoye", name: "linen-browser") { pullRequest(number: 2) { ...LinenPR } }"#))
            #expect(!query.contains("LOOKUPS"))
            let json = #"{"data":{"review":{"nodes":[\#(Self.pullRequest)]},"authored":{"nodes":[]},"recent":{"nodes":[]},"#
                + #""r0":{"pullRequest":\#(Self.pullRequest)},"r1":null},"errors":[{"message":"Could not resolve","type":"NOT_FOUND"}]}"#
            return Self.response(json, request: request)
        }
        let related = [URL(string: "https://github.com/kavoye/linen-browser/pull/2"), URL(string: "https://github.com/kavoye/gone/pull/9")]
            .compactMap(GitHubPullRequestReference.init(url:))
        let triage = try await client.triage(login: "octocat", repositories: [], related: related, token: "test")
        #expect(triage.reviewRequested.map(\.number) == [2])
        #expect(triage.related.map(\.number) == [2])
        await #expect(throws: GitHubFailure.self) {
            try await client.triage(login: "octo cat", repositories: [], related: [], token: "test")
        }
    }

    private nonisolated static let pullRequest = #"""
    {"id":"PR_2","number":2,"title":"Fix resizing","url":"https://github.com/kavoye/linen-browser/pull/2",
      "state":"OPEN","isDraft":false,"updatedAt":"2026-10-05T12:00:00Z","reviewDecision":"CHANGES_REQUESTED",
      "mergeable":"CONFLICTING","additions":24,"deletions":8,"changedFiles":3,"headRefName":"fix","baseRefName":"main",
      "author":{"login":"octocat"},"repository":{"nameWithOwner":"kavoye/linen-browser"},"comments":{"totalCount":4},
      "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"FAILURE"}}}]}}
    """#

    private nonisolated static let triage = #"{"data":{"review":{"nodes":[\#(pullRequest)]},"authored":{"nodes":[]},"recent":{"nodes":[]}}}"#

    private nonisolated static let notifications = #"""
    [{"id":"123","unread":true,"reason":"review_requested","updated_at":"2026-10-05T12:00:00Z",
      "subject":{"title":"Fix resizing","type":"PullRequest","url":"https://api.github.com/repos/kavoye/linen-browser/pulls/2"},
      "repository":{"full_name":"kavoye/linen-browser"}}]
    """#
}
