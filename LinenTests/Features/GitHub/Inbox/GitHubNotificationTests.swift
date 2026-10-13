// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Synchronization
import Testing

@testable import Linen

@MainActor
struct GitHubNotificationTests {
    @Test func changesNameWhatHappenedOnYourPullRequest() throws {
        let before = try GitHubFixtures.pullRequest(state: "OPEN", checks: "PENDING", review: "REVIEW_REQUIRED")
        let after = try Self.pullRequest(checks: "SUCCESS", review: "APPROVED", comments: 5)
        let updates = GitHubPRUpdate.changes(previous: [before.id: GitHubPRSnapshot(before)], authored: [after], activity: [])
        #expect(updates.count == 1)
        #expect(updates.first?.events == ["Approved", "Checks passed", "2 new comments"])

        let quiet = GitHubPRUpdate.changes(previous: [after.id: GitHubPRSnapshot(after)], authored: [after], activity: [])
        #expect(quiet.isEmpty)
        let active = GitHubPRUpdate.changes(previous: [after.id: GitHubPRSnapshot(after)], authored: [after], activity: [after.key])
        #expect(active.first?.events == ["New activity"])

        let failing = try Self.pullRequest(checks: "FAILURE", review: "CHANGES_REQUESTED", comments: 5, mergeable: "CONFLICTING")
        let worse = GitHubPRUpdate.changes(previous: [after.id: GitHubPRSnapshot(after)], authored: [failing], activity: [failing.key])
        #expect(worse.first?.events == ["Changes requested", "Checks failed", "Merge conflicts"])
    }

    @Test func yourOwnCommentIsNotNews() throws {
        let before = try Self.pullRequest(checks: "SUCCESS", review: "REVIEW_REQUIRED", comments: 3)
        let previous = [before.id: GitHubPRSnapshot(before)]
        let yours = try Self.pullRequest(checks: "SUCCESS", review: "REVIEW_REQUIRED", comments: 4, commenters: ["Mira"])
        #expect(GitHubPRUpdate.changes(previous: previous, authored: [yours], activity: [], login: "mira").isEmpty)

        let theirs = try Self.pullRequest(checks: "SUCCESS", review: "REVIEW_REQUIRED", comments: 4, commenters: ["octocat"])
        let updates = GitHubPRUpdate.changes(previous: previous, authored: [theirs], activity: [], login: "mira")
        #expect(updates.first?.events == ["1 new comment"])
    }

    @Test func commentsBeforeYourReplyAreStillNews() throws {
        let before = try Self.pullRequest(checks: "SUCCESS", review: "REVIEW_REQUIRED", comments: 3)
        let previous = [before.id: GitHubPRSnapshot(before)]
        let replied = try Self.pullRequest(checks: "SUCCESS", review: "REVIEW_REQUIRED", comments: 6, commenters: ["alex", "octocat", "mira"])
        let updates = GitHubPRUpdate.changes(previous: previous, authored: [replied], activity: [], login: "mira")
        #expect(updates.first?.events == ["2 new comments"])
    }

    @Test func aPullRequestPastTheInboxPageStillAnnounces() async throws {
        let box = GitHubTestCredentials()
        let id = UUID()
        try GitHubConnectionStore(profileID: id, storage: box.storage).save("test")
        let failing = Mutex<Set<Int>>([])
        let client = GitHubClient { request in
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            let json: String
            if request.url!.path == "/user" {
                json = #"{"login":"mira"}"#
            } else if request.url!.path == "/graphql" {
                let limit = body.firstMatch(of: /authored: search\(query: \$authored, type: ISSUE, first: (\d+)\)/).map { Int($0.1)! }
                    ?? body.firstMatch(of: /first: (\d+), after: \$cursor/).map { Int($0.1)! } ?? 0
                let nodes = (1...40).prefix(limit).map { number in
                    Self.json(checks: failing.withLock { $0.contains(number) } ? "FAILURE" : "SUCCESS")
                        .replacingOccurrences(of: "PR_42", with: "PR_\(number)")
                        .replacingOccurrences(of: #""number":42"#, with: #""number":\#(number)"#)
                        .replacingOccurrences(of: "/pull/42", with: "/pull/\(number)")
                }.joined(separator: ",")
                json = body.contains("LinenInbox(")
                    ? #"{"data":{"review":{"nodes":[]},"recent":{"nodes":[]},"authored":{"nodes":[\#(nodes)]}}}"#
                    : #"{"data":{"search":{"issueCount":40,"nodes":[\#(nodes)],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}"#
            } else {
                json = "[]"
            }
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let suite = TestDefaults.name("GitHubNotifyPage")
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var announced: [GitHubPRUpdate] = []
        let model = GitHubPanelModel(profileID: id, defaults: defaults, client: client, storage: box.storage)
        model.announce = { announced.append($0) }
        model.start()
        #expect(await waitUntil { model.lastUpdated != nil && !model.isRefreshing })
        failing.withLock { $0 = [35] }
        let previous = model.lastUpdated
        model.refresh()
        #expect(await waitUntil { model.lastUpdated != previous && !model.isRefreshing })
        #expect(announced.map(\.pr.number) == [35])
        #expect(announced.first?.events == ["Checks failed"])
        model.stop()
    }

    @Test func turningNotificationsBackOnDoesNotReplayOldChanges() async throws {
        let box = GitHubTestCredentials()
        let id = UUID()
        try GitHubConnectionStore(profileID: id, storage: box.storage).save("test")
        let checks = Mutex("PENDING")
        let client = GitHubClient { request in
            let json: String
            switch request.url!.path {
            case "/user":
                json = #"{"login":"mira"}"#
            case "/graphql" where String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("LinenPullRequests("):
                json = #"{"data":{"search":{"issueCount":1,"nodes":[\#(Self.json(checks: checks.withLock { $0 }))],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}"#
            case "/graphql":
                json = #"{"data":{"review":{"nodes":[]},"recent":{"nodes":[]},"authored":{"nodes":[\#(Self.json(checks: checks.withLock { $0 }))]}}}"#
            default:
                json = "[]"
            }
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let suite = TestDefaults.name("GitHubNotifyReplay")
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var announced: [GitHubPRUpdate] = []
        let model = GitHubPanelModel(profileID: id, defaults: defaults, client: client, storage: box.storage)
        model.announce = { announced.append($0) }
        model.start()
        #expect(await waitUntil { model.lastUpdated != nil && !model.isRefreshing })
        model.setNotifiesAboutPullRequests(false)
        checks.withLock { $0 = "FAILURE" }
        var previous = model.lastUpdated
        model.refresh()
        #expect(await waitUntil { model.lastUpdated != previous && !model.isRefreshing })
        model.setNotifiesAboutPullRequests(true)
        previous = model.lastUpdated
        model.refresh()
        #expect(await waitUntil { model.lastUpdated != previous && !model.isRefreshing })
        #expect(announced.isEmpty)
        model.stop()
    }

    @Test func firstRefreshOnlyRecordsAndLaterChangesAnnounceOnce() async throws {
        let box = GitHubTestCredentials()
        let id = UUID()
        try GitHubConnectionStore(profileID: id, storage: box.storage).save("test")
        let checks = Mutex("PENDING")
        let client = GitHubClient { request in
            let json: String
            switch request.url!.path {
            case "/user":
                json = #"{"login":"mira"}"#
            case "/graphql" where String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("LinenPullRequests("):
                json = #"{"data":{"search":{"issueCount":1,"nodes":[\#(Self.json(checks: checks.withLock { $0 }))],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}"#
            case "/graphql":
                json = #"{"data":{"review":{"nodes":[]},"recent":{"nodes":[]},"authored":{"nodes":[\#(Self.json(checks: checks.withLock { $0 }))]}}}"#
            default:
                json = "[]"
            }
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let suite = TestDefaults.name("GitHubNotify")
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var announced: [GitHubPRUpdate] = []
        let model = GitHubPanelModel(profileID: id, defaults: defaults, client: client, storage: box.storage)
        model.announce = { announced.append($0) }
        model.start()
        #expect(await waitUntil { model.lastUpdated != nil })
        #expect(announced.isEmpty)

        checks.withLock { $0 = "SUCCESS" }
        var previous = model.lastUpdated
        model.refresh()
        #expect(await waitUntil { model.lastUpdated != previous })
        #expect(announced.map(\.events) == [["Checks passed"]])

        previous = model.lastUpdated
        model.refresh()
        #expect(await waitUntil { model.lastUpdated != previous })
        #expect(announced.count == 1)

        model.setNotifiesAboutPullRequests(false)
        checks.withLock { $0 = "FAILURE" }
        previous = model.lastUpdated
        model.refresh()
        #expect(await waitUntil { model.lastUpdated != previous })
        #expect(announced.count == 1)
        model.stop()

        let restored = GitHubPanelModel(profileID: id, defaults: defaults, client: client, storage: box.storage)
        #expect(!restored.notifiesAboutPullRequests)
        restored.setNotifiesAboutPullRequests(true)
        restored.announce = { announced.append($0) }
        checks.withLock { $0 = "SUCCESS" }
        restored.start()
        #expect(await waitUntil { restored.lastUpdated != nil })
        #expect(announced.count == 1)
        checks.withLock { $0 = "ERROR" }
        previous = restored.lastUpdated
        restored.refresh()
        #expect(await waitUntil { restored.lastUpdated != previous })
        #expect(announced.last?.events == ["Checks failed"])
        restored.disconnect()
    }

    @Test(arguments: ["000000", "fbca04", "ffffff", "0e8a16", "5319e7", "ededed"])
    func labelInkStaysReadableInBothAppearances(color: String) {
        let label = GitHubInboxPR.Label(name: "label", color: color)
        #expect(GitHubInboxPR.Label.luminance(label.ink(dark: true)) >= 0.45)
        #expect(GitHubInboxPR.Label.luminance(label.ink(dark: false)) <= 0.18)
    }

    private static func pullRequest(
        checks: String, review: String, comments: Int, mergeable: String = "MERGEABLE", commenters: [String] = []
    ) throws -> GitHubInboxPR {
        let json = Self.json(checks: checks, review: review, comments: comments, mergeable: mergeable, commenters: commenters)
        return try GitHubClient.decoder().decode(GitHubInboxPR.self, from: Data(json.utf8))
    }

    private nonisolated static func json(
        checks: String, review: String = "REVIEW_REQUIRED", comments: Int = 3, mergeable: String = "MERGEABLE",
        commenters: [String] = []
    ) -> String {
        let authors = commenters.map { #"{"author":{"login":"\#($0)"}}"# }.joined(separator: ",")
        let nodes = commenters.isEmpty ? "" : #","nodes":[\#(authors)]"#
        return #"""
        {"id":"PR_42","number":42,"title":"Add keyboard shortcuts","url":"https://github.com/kavoye/linen-browser/pull/42",
         "state":"OPEN","isDraft":false,"updatedAt":"2026-10-06T00:20:00Z","reviewDecision":"\#(review)",
         "mergeable":"\#(mergeable)","additions":1,"deletions":1,"changedFiles":1,"headRefName":"keys","baseRefName":"main",
         "author":{"login":"mira"},"repository":{"nameWithOwner":"kavoye/linen-browser"},"comments":{"totalCount":\#(comments)\#(nodes)},
         "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"\#(checks)"}}}]}}
        """#
    }
}
