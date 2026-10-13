// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@MainActor
struct GitHubPRDetailsTests {
    @Test func detailsKeepTheSignalAndMarkBots() async throws {
        let client = GitHubClient { request in
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
            let variables = body?["variables"] as? [String: Any]
            #expect(variables?["owner"] as? String == "kavoye")
            #expect(variables?["number"] as? Int == 42)
            let query = try #require(body?["query"] as? String)
            #expect(!query.contains("on Team") && !query.contains("TEAMS"))
            return (Data(GitHubFixtures.details.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let reference = try #require(GitHubPullRequestReference(url: URL(string: "https://github.com/kavoye/linen-browser/pull/42")))
        let details = try await client.pullRequestDetails(reference, token: "test")

        #expect(details.checks.map(\.name) == ["build-macos", "lint", "ci/buildkite", "docs"])
        #expect(details.checks.map(\.state) == [.failed, .pending, .passed, .skipped])
        #expect(details.checks[0].title == "CI / build-macos (pull_request)")
        #expect(details.checks[0].duration == 120)
        #expect(details.checks[0].iconURL?.host == "avatars.githubusercontent.com")
        #expect(details.checks[1].duration == nil)
        #expect(details.checks[1].url == nil)
        #expect(details.checks[2].url?.host == "buildkite.com")

        #expect(details.reviews == [GitHubPRDetails.Review(author: .init(login: "mira", isBot: false), state: "CHANGES_REQUESTED")])
        #expect(details.pendingReviewers.map(\.login) == ["alex"])
        #expect(details.hiddenTeams == 1)

        #expect(details.threads.count == 3)
        #expect(details.threads.last?.path == "Linen/Old.swift")
        #expect(details.threads.filter(\.isBot).map(\.author?.login) == ["coderabbitai"])
        #expect(details.threads.contains { $0.author?.login == "mira" && $0.line == 120 })

        #expect(details.comments.map(\.author?.login) == ["renovate[bot]", "copilot-pull-request-reviewer", "alex"])
        #expect(details.comments.map(\.isBot) == [true, true, false])
        #expect(details.comments[1].url == nil)

        #expect(details.fileCount == 3)
        #expect(details.files.first?.anchor == "diff-f863b2cae0cafc8013e15e8015fb3b7e629edc1ca7b18be1260988c5d0e11aa9")
        #expect(details.issues.map(\.number) == [12])
        #expect(details.mergeState == "BEHIND")
        #expect(details.summary.hasSuffix("- Adds tests for each stand-in."))
        #expect(details.comments.last?.markdown == "Looks close. Can we cap the height on small windows?")
        #expect(details.comments.last?.author?.avatarURL?.host == "avatars.githubusercontent.com")
    }

    @Test func teamNamesAreReadOnlyWithOrganizationAccess() async throws {
        let client = GitHubClient { request in
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
            #expect((body?["query"] as? String)?.contains("... on Team { name avatarUrl(size: 64) }") == true)
            let json = GitHubFixtures.details.replacingOccurrences(of: #"{"kind":"Team"}"#, with: #"{"kind":"Team","name":"core"}"#)
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let reference = try #require(GitHubPullRequestReference(url: URL(string: "https://github.com/kavoye/linen-browser/pull/42")))
        let details = try await client.pullRequestDetails(reference, includeTeams: true, token: "test")
        #expect(details.pendingReviewers.map(\.login) == ["alex", "core"])
        #expect(details.hiddenTeams == 0)
    }

    @Test func digestLeadsWithWhatBlocksTheMerge() async throws {
        let pr = try GitHubFixtures.pullRequest(state: "OPEN", checks: "FAILURE", review: "CHANGES_REQUESTED")
        let digest = GitHubPRDigest(pr: pr, details: try await loadDetails())
        #expect(digest.tone == .danger)
        #expect(digest.rows.map(\.kind) == [.review, .checks, .threads, .comments, .conflicts, .base])
        #expect(digest.rows.map(\.tone) == [.danger, .danger, .warning, .neutral, .success, .warning])
        #expect(digest.rows[1].detail?.contains("1 failing") == true)
        #expect(digest.rows[1].detail?.contains("1 skipped") == true)
        #expect(digest.rows.filter(\.expandable).map(\.kind) == [.review, .checks, .threads, .comments])
    }

    @Test func requiredReviewBlocksAPassingPullRequest() throws {
        let pr = try GitHubFixtures.pullRequest(state: "OPEN", checks: "SUCCESS", review: "REVIEW_REQUIRED")
        let check = GitHubPRDetails.Check(name: "formatting", state: .passed, url: nil, date: nil, workflow: "Lint", event: "pull_request")
        let details = GitHubPRDetails(summary: "", mergeState: "BLOCKED", checks: [check], reviews: [], pendingReviewers: [],
                                      threads: [], comments: [], files: [], fileCount: 0, issues: [], updatedAt: .now)
        let digest = GitHubPRDigest(pr: pr, details: details)
        #expect(digest.tone == .warning)
        #expect(digest.rows.first?.kind == .review)
        #expect(digest.rows.first?.tone == .warning)
        #expect(digest.rows.first?.symbol == "minus.circle.fill")
        #expect(digest.rows.first?.detail != nil)
        #expect(digest.rows[1].tone == .success)
        #expect(check.title == "Lint / formatting (pull_request)")
    }

    @Test func theVerdictNamesTheFirstThingThatBlocksTheMerge() throws {
        let failing = [GitHubPRDetails.Check(name: "build", state: .failed, url: nil, date: nil)]
        let cases: [VerdictCase] = [
            VerdictCase(pr: try Self.pr(state: "MERGED"), details: nil, verdict: "Merged", tone: .success),
            VerdictCase(pr: try Self.pr(state: "CLOSED"), details: nil, verdict: "Closed", tone: .neutral),
            VerdictCase(pr: try Self.pr(conflicting: true), details: Self.details(checks: failing), verdict: "Merge conflicts", tone: .danger),
            VerdictCase(pr: try Self.pr(review: "CHANGES_REQUESTED"), details: Self.details(checks: failing), verdict: "Checks failed", tone: .danger),
            VerdictCase(pr: try Self.pr(checks: "FAILURE", review: "CHANGES_REQUESTED"), details: nil, verdict: "Checks failed", tone: .danger),
            VerdictCase(pr: try Self.pr(review: "CHANGES_REQUESTED", draft: true), details: nil, verdict: "Changes requested", tone: .warning),
            VerdictCase(pr: try Self.pr(review: "REVIEW_REQUIRED", draft: true), details: nil, verdict: nil, tone: .neutral),
            VerdictCase(pr: try Self.pr(checks: "PENDING", review: "REVIEW_REQUIRED"), details: nil, verdict: "Review required", tone: .warning),
            VerdictCase(pr: try Self.pr(checks: "PENDING"), details: nil, verdict: "Checks running", tone: .neutral),
            VerdictCase(pr: try Self.pr(), details: Self.details(threads: 2, mergeState: "BLOCKED"), verdict: "2 open threads", tone: .warning),
            VerdictCase(pr: try Self.pr(), details: Self.details(mergeState: "BLOCKED"), verdict: "Blocked", tone: .danger),
            VerdictCase(pr: try Self.pr(), details: Self.details(), verdict: "Ready to merge", tone: .success),
        ]
        for item in cases {
            let digest = GitHubPRDigest(pr: item.pr, details: item.details)
            #expect(digest.verdict.map { String(localized: $0) } == item.verdict)
            #expect(digest.tone == item.tone, "\(item.verdict ?? "draft")")
        }
    }

    @Test func theReviewRowSaysWhoTheMergeIsWaitingOn() throws {
        let mira = GitHubPRDetails.Actor(login: "mira", isBot: false)
        let alex = GitHubPRDetails.Actor(login: "alex", isBot: false)
        let row = { (pr: GitHubInboxPR, details: GitHubPRDetails) in
            try #require(GitHubPRDigest(pr: pr, details: details).rows.first { $0.kind == .review })
        }

        let blocked = try row(try Self.pr(), Self.details(reviews: [.init(author: mira, state: "CHANGES_REQUESTED")]))
        #expect(blocked.tone == .danger)
        #expect(String(localized: blocked.title) == "Changes requested by mira")

        let partly = try row(try Self.pr(review: "REVIEW_REQUIRED"), Self.details(reviews: [.init(author: alex, state: "APPROVED")]))
        #expect(partly.tone == .warning)
        #expect(partly.detail == "Approved by alex. Needs more approvals.")
        #expect(partly.symbol == "minus.circle.fill")

        let approved = try row(try Self.pr(), Self.details(reviews: [.init(author: alex, state: "APPROVED")]))
        #expect(approved.tone == .success)
        #expect(String(localized: approved.title) == "Approved by alex")

        let waiting = try row(try Self.pr(), Self.details(pending: [mira]))
        #expect(String(localized: waiting.title) == "Waiting on mira")
        #expect(String(localized: try row(try Self.pr(), Self.details(hiddenTeams: 1)).title) == "Waiting on a team")

        let quiet = try row(try Self.pr(), Self.details())
        #expect(String(localized: quiet.title) == "No reviews yet")
        #expect(!quiet.expandable)
    }

    @Test func theCheckAndBranchRowsFollowTheirState() throws {
        let rows = { (details: GitHubPRDetails) in GitHubPRDigest(pr: try Self.pr(), details: details).rows }
        let checks = { (details: GitHubPRDetails) in try #require(try rows(details).first { $0.kind == .checks }) }

        #expect(String(localized: try checks(Self.details()).title) == "No checks")
        let running = try checks(Self.details(checks: [.init(name: "lint", state: .pending, url: nil, date: nil)]))
        #expect(running.tone == .warning)
        #expect(running.symbol == "clock.fill")
        let passed = try checks(Self.details(checks: [
            .init(name: "lint", state: .passed, url: nil, date: nil), .init(name: "test", state: .passed, url: nil, date: nil),
        ]))
        #expect(passed.tone == .success)
        #expect(passed.detail == "2 successful checks")

        let behind = try rows(Self.details(mergeState: "BEHIND")).first { $0.kind == .base }
        #expect(behind?.tone == .warning)
        #expect(behind.map { String(localized: $0.title) } == "Behind main")
        #expect(try rows(Self.details(mergeState: "UNKNOWN")).contains { $0.kind == .base } == false)
        let current = try rows(Self.details()).first { $0.kind == .base }
        #expect(current.map { String(localized: $0.title) } == "Up to date with main")
        #expect(try rows(Self.details()).first { $0.kind == .conflicts }?.tone == .success)
    }

    private struct VerdictCase {
        let pr: GitHubInboxPR
        let details: GitHubPRDetails?
        let verdict: String?
        let tone: GitHubPRDigest.Tone
    }

    private static func pr(
        state: String = "OPEN", checks: String? = "SUCCESS", review: String? = "APPROVED",
        conflicting: Bool = false, draft: Bool = false
    ) throws -> GitHubInboxPR {
        var json = GitHubFixtures.pullRequestJSON(state: state, checks: checks, review: review)
        if conflicting {
            json = json.replacingOccurrences(of: #""mergeable":"MERGEABLE""#, with: #""mergeable":"CONFLICTING""#)
        }
        if draft {
            json = json.replacingOccurrences(of: #""isDraft":false"#, with: #""isDraft":true"#)
        }
        return try GitHubClient.decoder().decode(GitHubInboxPR.self, from: Data(json.utf8))
    }

    private static func details(
        checks: [GitHubPRDetails.Check] = [], reviews: [GitHubPRDetails.Review] = [], pending: [GitHubPRDetails.Actor] = [],
        hiddenTeams: Int = 0, threads: Int = 0, mergeState: String? = "CLEAN"
    ) -> GitHubPRDetails {
        let open = (0..<threads).map {
            GitHubPRDetails.Comment(author: nil, text: "Thread \($0)", url: URL(string: "https://github.com/a/b/pull/1#r\($0)"), date: nil)
        }
        return GitHubPRDetails(summary: "", mergeState: mergeState, checks: checks, reviews: reviews, pendingReviewers: pending,
                               hiddenTeams: hiddenTeams, threads: open, comments: [], files: [], fileCount: 0, issues: [], updatedAt: .now)
    }

    @Test func digestWithoutDetailsUsesTheListData() throws {
        let running = GitHubPRDigest(pr: try GitHubFixtures.pullRequest(state: "OPEN", checks: "PENDING", review: nil), details: nil)
        #expect(running.tone == .neutral)
        #expect(running.rows.map(\.kind) == [.conflicts])
        let merged = GitHubPRDigest(pr: try GitHubFixtures.pullRequest(state: "MERGED", checks: "SUCCESS", review: "APPROVED"), details: nil)
        #expect(merged.tone == .success)
        #expect(merged.rows.isEmpty)
        let approved = try GitHubFixtures.pullRequest(state: "OPEN", checks: "SUCCESS", review: "APPROVED")
        #expect(approved.author?.avatarURL?.host == "avatars.githubusercontent.com")
        #expect(approved.checkCounts?.passed == 11)
        #expect(approved.checkCounts?.total == 12)
        #expect(try GitHubFixtures.pullRequest(state: "OPEN", checks: nil, review: nil).checkCounts == nil)
        #expect(approved.baseLabel == "kavoye:main")
        #expect(approved.headLabel == "mira:keyboard-shortcuts")
        #expect(approved.labelList.map(\.name) == ["bug", "odd"])
        #expect(approved.labelList[0].rgb?.red == 0xd7 / 255.0)
        #expect(approved.labelList[1].rgb == nil)
        let ready = GitHubPRDigest(pr: approved, details: nil)
        #expect(ready.tone == .success)
    }

    @Test func tabPreviewFetchesAnyPullRequestAndCachesIt() async throws {
        let box = GitHubTestCredentials()
        let id = UUID()
        try GitHubConnectionStore(profileID: id, storage: box.storage).save("test")
        let pr = try GitHubFixtures.pullRequest(state: "OPEN", checks: "SUCCESS", review: "REVIEW_REQUIRED")
        let client = GitHubClient { request in
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            let json: String
            if request.url!.path == "/user" {
                json = #"{"login":"octocat"}"#
            } else if body.contains("LinenPullRequestDetails(") {
                json = GitHubFixtures.details
            } else if body.contains("LinenPullRequest($") {
                json = #"{"data":{"repository":{"pullRequest":\#(GitHubFixtures.pullRequestJSON(state: "OPEN", checks: "SUCCESS", review: "REVIEW_REQUIRED"))}}}"#
            } else if request.url!.path == "/graphql" {
                json = #"{"data":{"review":{"nodes":[]},"authored":{"nodes":[]},"recent":{"nodes":[]}}}"#
            } else {
                json = "[]"
            }
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let suite = TestDefaults.name("GitHubTabPreview")
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = GitHubPanelModel(profileID: id, defaults: defaults, client: client, storage: box.storage)
        model.start()
        #expect(await waitUntil { model.lastUpdated != nil })
        let reference = try #require(GitHubPullRequestReference(url: pr.url))
        #expect(model.cachedPreview(reference) == nil)
        await model.refreshPreview(reference)
        #expect(model.cachedPreview(reference)?.pr == pr)
        #expect(await waitUntil { model.cachedPreview(reference)?.details != nil })
        model.disconnect()
        #expect(model.cachedPreview(reference) == nil)
    }

    @Test func descriptionMarkdownDropsGitHubOnlyMarkup() {
        let source = """
        <!-- Thanks for contributing! Fill in the template. -->
        ## Summary\r
        Fixes startup.<br>Second line.

        <details><summary>Logs</summary>

        ```swift
        let values: Array<Int> = []
        ```
        </details>

        ![screenshot](https://user-images.githubusercontent.com/1.png)
        - [x] Tests
        - [ ] Docs



        Done
        """
        let readable = GitHubPRDetails.readable(source)
        #expect(!readable.contains("<!--") && !readable.contains("Thanks for contributing"))
        #expect(readable.hasPrefix("## Summary\nFixes startup.\nSecond line."))
        #expect(readable.contains("**Logs**"))
        #expect(!readable.contains("<details>") && !readable.contains("</details>"))
        #expect(readable.contains("Array<Int>"))
        #expect(!readable.contains("screenshot"))
        #expect(readable.contains("☑ Tests\n☐ Docs"))
        #expect(!readable.contains("- ☑"))
        #expect(!readable.contains("\n\n\n"))
    }

    @Test func botsAreRecognisedByTypeOrSuffix() {
        #expect(GitHubPRDetails.isBot(login: "copilot-pull-request-reviewer", kind: "Bot"))
        #expect(GitHubPRDetails.isBot(login: "renovate[bot]", kind: "User"))
        #expect(!GitHubPRDetails.isBot(login: "mira", kind: "User"))
    }

    private func loadDetails() async throws -> GitHubPRDetails {
        let client = GitHubClient { request in
            (Data(GitHubFixtures.details.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let reference = try #require(GitHubPullRequestReference(url: URL(string: "https://github.com/kavoye/linen-browser/pull/42")))
        return try await client.pullRequestDetails(reference, token: "test")
    }
}

nonisolated enum GitHubFixtures {
    static func pullRequest(state: String, checks: String?, review: String?) throws -> GitHubInboxPR {
        try GitHubClient.decoder().decode(GitHubInboxPR.self, from: Data(pullRequestJSON(state: state, checks: checks, review: review).utf8))
    }

    static func pullRequestJSON(state: String, checks: String?, review: String?) -> String {
        let runs = #"[{"state":"SUCCESS","count":10},{"state":"SKIPPED","count":1},{"state":"FAILURE","count":1}]"#
        let counts = #"{"totalCount":13,"checkRunCountsByState":\#(runs),"statusContextCountsByState":[{"state":"SUCCESS","count":1}]}"#
        let rollup = checks.map { #"{"state":"\#($0)","contexts":\#(counts)}"# } ?? "null"
        let decision = review.map { #""\#($0)""# } ?? "null"
        let json = #"""
        {"id":"PR_42","number":42,"title":"Add keyboard shortcuts","url":"https://github.com/kavoye/linen-browser/pull/42",
         "state":"\#(state)","isDraft":false,"createdAt":"2026-10-01T09:00:00Z","updatedAt":"2026-10-06T00:20:00Z",
         "reviewDecision":\#(decision),"mergeable":"MERGEABLE","additions":263,"deletions":1,"changedFiles":3,
         "headRefName":"keyboard-shortcuts","baseRefName":"main","author":{"login":"mira","avatarUrl":"https://avatars.githubusercontent.com/u/2?v=4"},
         "headRepositoryOwner":{"login":"mira"},"labels":{"nodes":[{"name":"bug","color":"d73a4a"},{"name":"odd","color":"zz"}]},
         "repository":{"nameWithOwner":"kavoye/linen-browser"},"comments":{"totalCount":3},
         "commits":{"nodes":[{"commit":{"statusCheckRollup":\#(rollup)}}]}}
        """#
        return json
    }

    static let details = #"""
    {"data":{"repository":{"pullRequest":{
      "body":"## Summary\nStubs the `chrome.privacy` APIs **iCloud Passwords** needs at startup. See [run 42](https://github.com/kavoye/linen-browser/actions/runs/42).\n\n- Adds tests for each stand-in.",
      "updatedAt":"2026-10-06T00:20:00Z","mergeStateStatus":"BEHIND",
      "reviewRequests":{"nodes":[{"requestedReviewer":{"kind":"User","login":"alex"}},{"requestedReviewer":{"kind":"Team"}}]},
      "latestOpinionatedReviews":{"nodes":[{"state":"CHANGES_REQUESTED","author":{"kind":"User","login":"mira"}}]},
      "reviewThreads":{"nodes":[
        {"isResolved":false,"isOutdated":true,"path":"Linen/Old.swift","line":null,"comments":{"nodes":[
          {"author":{"kind":"User","login":"mira"},"bodyText":"This moved.","url":"https://github.com/kavoye/linen-browser/pull/42#discussion_r1","createdAt":"2026-10-05T08:00:00Z"}]}},
        {"isResolved":true,"isOutdated":false,"path":"Linen/Done.swift","line":4,"comments":{"nodes":[
          {"author":{"kind":"User","login":"mira"},"bodyText":"Fixed.","url":"https://github.com/kavoye/linen-browser/pull/42#discussion_r4","createdAt":"2026-10-05T08:00:00Z"}]}},
        {"isResolved":false,"isOutdated":false,"path":"Linen/Extensions/ExtensionShims.swift","line":120,"comments":{"nodes":[
          {"author":{"kind":"User","login":"mira"},"bodyText":"Can this leak the port when the page reloads?","url":"https://github.com/kavoye/linen-browser/pull/42#discussion_r2","createdAt":"2026-10-05T09:00:00Z"}]}},
        {"isResolved":false,"isOutdated":false,"path":"Linen/Extensions/ExtensionPage.swift","line":3,"comments":{"nodes":[
          {"author":{"kind":"Bot","login":"coderabbitai"},"bodyText":"Nitpick: consider renaming this.","url":"https://github.com/kavoye/linen-browser/pull/42#discussion_r3","createdAt":"2026-10-05T10:00:00Z"}]}}
      ]},
      "comments":{"nodes":[
        {"author":{"kind":"User","login":"alex","avatarUrl":"https://avatars.githubusercontent.com/u/3?v=4"},"bodyText":"Looks close. Can we cap the height on small windows?","url":"https://github.com/kavoye/linen-browser/pull/42#issuecomment-1","createdAt":"2026-10-05T09:00:00Z"},
        {"author":{"kind":"Bot","login":"copilot-pull-request-reviewer"},"bodyText":"Pull request overview\nThis PR adds…","url":"https://evil.test/x","createdAt":"2026-10-05T11:00:00Z"},
        {"author":{"kind":"User","login":"renovate[bot]"},"bodyText":"Dependency dashboard","url":"https://github.com/kavoye/linen-browser/pull/42#issuecomment-3","createdAt":"2026-10-05T12:00:00Z"}
      ]},
      "files":{"totalCount":3,"nodes":[
        {"path":"Linen/Extensions/ExtensionShims.swift","additions":200,"deletions":1},
        {"path":"Linen/Extensions/ExtensionPage.swift","additions":50,"deletions":0},
        {"path":"LinenTests/Extensions/ShimTests.swift","additions":13,"deletions":0}
      ]},
      "closingIssuesReferences":{"nodes":[{"number":12,"title":"iCloud Passwords never starts","url":"https://github.com/kavoye/linen-browser/issues/12"}]},
      "commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"nodes":[
        {"kind":"CheckRun","name":"build-macos","status":"COMPLETED","conclusion":"SUCCESS","detailsUrl":"https://github.com/kavoye/linen-browser/actions/runs/1",
         "completedAt":"2026-10-05T11:00:00Z",
         "checkSuite":{"app":{"logoUrl":"https://avatars.githubusercontent.com/in/15368?v=4"},"workflowRun":{"event":"pull_request","workflow":{"name":"CI"}}}},
        {"kind":"CheckRun","name":"build-macos","status":"COMPLETED","conclusion":"FAILURE","detailsUrl":"https://github.com/kavoye/linen-browser/actions/runs/2",
         "startedAt":"2026-10-05T11:58:00Z","completedAt":"2026-10-05T12:00:00Z",
         "checkSuite":{"app":{"logoUrl":"https://avatars.githubusercontent.com/in/15368?v=4"},"workflowRun":{"event":"pull_request","workflow":{"name":"CI"}}}},
        {"kind":"CheckRun","name":"lint","status":"IN_PROGRESS","conclusion":null,"detailsUrl":"http://insecure.test/lint","completedAt":null},
        {"kind":"CheckRun","name":"docs","status":"COMPLETED","conclusion":"SKIPPED","detailsUrl":null,"completedAt":null},
        {"kind":"StatusContext","context":"ci/buildkite","state":"SUCCESS","targetUrl":"https://buildkite.com/kavoye/linen","createdAt":"2026-10-05T10:00:00Z"}
      ]}}}}]}
    }}}}
    """#
}
