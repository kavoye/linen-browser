// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import CoreGraphics
import Foundation
import Testing

@testable import Linen

@MainActor
struct GitHubInboxTests {
    private let now = Date(timeIntervalSince1970: 1_791_288_000)

    @Test func needsYouMergesNotificationsWithReviewRequests() throws {
        let review = try pr(1, author: "mira")
        let mentioned = try pr(2, author: "alex")
        let waiting = try pr(3, author: "sam")
        let sections = GitHubInboxSection.build(
            triage: GitHubTriage(reviewRequested: [review, waiting], related: [mentioned]),
            notifications: [try notification("10", reason: "review_requested", number: 1), try notification("11", reason: "mention", number: 2)],
            login: "octocat", now: now
        )
        let needsYou = try #require(sections.first { $0.kind == .needsYou })
        #expect(needsYou.items.map(\.number) == [2, 1, 3])
        #expect(needsYou.items.map(\.reason) == [.mentioned, .reviewRequested, .reviewRequested])
        #expect(needsYou.items.map(\.isUnread) == [true, true, false])
        #expect(needsYou.items[0].pr == mentioned)
    }

    @Test func commentsOnYourPullRequestsNeedYouAndStayOnTheBoard() throws {
        let passing = try pr(4, author: "OctoCat", checks: "SUCCESS", updated: "2026-10-06T11:00:00Z")
        let failing = try pr(5, author: "octocat", checks: "FAILURE")
        let approved = try pr(6, author: "octocat", review: "APPROVED")
        let sections = GitHubInboxSection.build(
            triage: GitHubTriage(authored: [passing, failing, approved]),
            notifications: [try notification("12", reason: "comment", number: 4)],
            login: "octocat", now: now
        )
        #expect(sections.map(\.kind) == [.needsYou, .authored])
        #expect(sections[0].items.first?.reason == .yourPullRequest)
        #expect(sections[1].items.map(\.number) == [5, 6, 4])
        #expect(sections[1].items.map(\.isUnread) == [false, false, true])
    }

    @Test func recentlyOpenedSkipsYoursAndWatchedThreadsJoinIt() throws {
        let watched = try pr(7, author: "mira", created: "2026-10-05T09:00:00Z")
        let old = try pr(8, author: "mira", created: "2026-09-01T09:00:00Z")
        let searched = try pr(9, author: "alex", created: "2026-10-06T09:00:00Z")
        let mine = try pr(10, author: "octocat", created: "2026-10-06T10:00:00Z")
        let sections = GitHubInboxSection.build(
            triage: GitHubTriage(recent: [searched, mine], related: [watched, old]),
            notifications: [try notification("13", reason: "subscribed", number: 7), try notification("14", reason: "subscribed", number: 8)],
            login: "octocat", now: now
        )
        #expect(sections.map(\.kind) == [.recent, .other])
        #expect(sections[0].items.map(\.number) == [9, 7])
        #expect(sections[0].items.map(\.reason) == [.opened, .opened])
        #expect(sections[1].items.map(\.number) == [8])
    }

    @Test func previewBelongsToTheRowThatOpenedIt() throws {
        let presenter = GitHubPreviewPresenter()
        let first = GitHubInboxItem(id: "a", reason: .opened, pr: try pr(1, author: "mira"), notification: nil)
        let second = GitHubInboxItem(id: "b", reason: .opened, pr: try pr(2, author: "alex"), notification: nil)
        presenter.moved("a", anchor: CGRect(x: 0, y: 0, width: 10, height: 10))
        presenter.moved("b", anchor: CGRect(x: 0, y: 40, width: 10, height: 10))
        presenter.show(first, rowID: "a")
        presenter.show(second, rowID: "b")
        presenter.hide("a")
        #expect(presenter.shown?.item == second)
        presenter.moved("a", anchor: .zero)
        #expect(presenter.shown?.anchor.minY == 40)
        presenter.moved("b", anchor: CGRect(x: 0, y: 80, width: 10, height: 10))
        #expect(presenter.shown?.anchor.minY == 80)
        presenter.dismiss()
        #expect(presenter.shown == nil)
    }

    @Test func commentPreviewsCoverThreadsButNotPullRequestActivity() throws {
        let watched = try pr(1, author: "mira")
        let sections = GitHubInboxSection.build(
            triage: GitHubTriage(related: [watched]),
            notifications: [
                try notification("20", reason: "comment", number: 1),
                try notification("21", reason: "subscribed", number: 1),
                try notification("22", reason: "comment", number: 5, type: "Issue"),
                try notification("23", reason: "subscribed", number: 6, type: "Release"),
            ],
            login: "octocat", now: now
        )
        let items = sections.flatMap(\.items)
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        #expect(byID["n-20"]?.showsThread == true)
        #expect(byID["n-21"]?.showsThread == false)
        #expect(byID["n-22"]?.showsThread == true)
        #expect(byID["n-23"]?.showsThread == false)
        #expect(byID["n-22"]?.notification?.thread == GitHubThreadSubject(
            kind: .issueOrPullRequest, owner: "kavoye", name: "linen-browser", number: 5, title: "Thread 5"
        ))
    }

    @Test func avatarCacheFetchesEachImageOnce() async throws {
        let png = try #require(NSImage(size: NSSize(width: 4, height: 4), flipped: false) { _ in
            NSColor.red.setFill()
            NSRect(x: 0, y: 0, width: 4, height: 4).fill()
            return true
        }.tiffRepresentation)
        let fetches = FetchCounter()
        let cache = GitHubImageCache { url in
            await fetches.record(url)
            let status = url.lastPathComponent == "missing" ? 404 : 200
            return (png, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        let avatar = URL(string: "https://avatars.githubusercontent.com/u/1")!
        async let first = cache.image(for: avatar)
        async let second = cache.image(for: avatar)
        let (a, b) = await (first, second)
        #expect(a != nil && a === b)
        #expect(cache.cached(avatar) === a)
        #expect(await cache.image(for: avatar) === a)
        #expect(await fetches.count(avatar) == 1)

        let missing = URL(string: "https://avatars.githubusercontent.com/missing")!
        #expect(await cache.image(for: missing) == nil)
        #expect(cache.cached(missing) == nil)
        #expect(await cache.image(for: missing) == nil)
        #expect(await fetches.count(missing) == 1)

        let later = Date().addingTimeInterval(301)
        cache.now = { later }
        #expect(await cache.image(for: missing) == nil)
        #expect(await fetches.count(missing) == 2)
    }

    @Test func inboxIsTheDefaultViewAndCannotBeDeleted() {
        let model = GitHubPanelModel(profileID: UUID(), defaults: UserDefaults(suiteName: TestDefaults.name("GitHubInbox"))!)
        #expect(model.isInbox)
        model.deleteFilter(GitHubFilter.inboxID)
        #expect(model.filters.count == GitHubFilter.defaults.count)
        model.selectFilter("review")
        #expect(!model.isInbox)
        model.deleteFilter("assigned")
        #expect(model.selectedFilterID == "review")
        #expect(!model.filters.contains { $0.id == "assigned" })
        model.deleteFilter("review")
        #expect(model.isInbox)
    }

    @Test func selectingAnItemKeepsItsDetailAndOpensOtherSubjects() throws {
        let model = GitHubPanelModel(profileID: UUID(), defaults: UserDefaults(suiteName: TestDefaults.name("GitHubInbox"))!)
        let review = try pr(1, author: "mira")
        model.select(GitHubInboxItem(id: "review-1", reason: .reviewRequested, pr: review, notification: nil)) { _ in
            Issue.record("A pull request opens in the panel")
        }
        #expect(model.selectedItemID == "review-1")
        #expect(model.selectedPR == review)
        var opened: URL?
        let issue = try notification("15", reason: "mention", number: 3, type: "Issue")
        model.select(GitHubInboxItem(id: "n-15", reason: .mentioned, pr: nil, notification: issue)) { opened = $0 }
        #expect(opened?.absoluteString == "https://github.com/kavoye/linen-browser/issues/3")
        #expect(model.selectedPR == review)
        model.clearSelection()
        #expect(model.selectedPR == nil)
    }

    private func pr(
        _ number: Int, author: String, checks: String? = nil, review: String? = nil,
        created: String = "2026-09-20T09:00:00Z", updated: String = "2026-10-06T09:00:00Z"
    ) throws -> GitHubInboxPR {
        let rollup = checks.map { #"{"state":"\#($0)"}"# } ?? "null"
        let decision = review.map { #""\#($0)""# } ?? "null"
        let json = #"""
        {"id":"PR_\#(number)","number":\#(number),"title":"Change \#(number)","url":"https://github.com/kavoye/linen-browser/pull/\#(number)",
         "state":"OPEN","isDraft":false,"createdAt":"\#(created)","updatedAt":"\#(updated)","reviewDecision":\#(decision),
         "mergeable":"MERGEABLE","additions":1,"deletions":1,"changedFiles":1,"headRefName":"head","baseRefName":"main",
         "author":{"login":"\#(author)"},"repository":{"nameWithOwner":"kavoye/linen-browser"},"comments":{"totalCount":0},
         "commits":{"nodes":[{"commit":{"statusCheckRollup":\#(rollup)}}]}}
        """#
        return try GitHubClient.decoder().decode(GitHubInboxPR.self, from: Data(json.utf8))
    }

    private func notification(_ id: String, reason: String, number: Int, type: String = "PullRequest") throws -> GitHubNotification {
        let path = type == "Issue" ? "issues" : "pulls"
        let json = #"""
        {"id":"\#(id)","unread":true,"reason":"\#(reason)","updated_at":"2026-10-06T10:\#(id):00Z",
         "subject":{"title":"Thread \#(number)","type":"\#(type)","url":"https://api.github.com/repos/kavoye/linen-browser/\#(path)/\#(number)"},
         "repository":{"full_name":"kavoye/linen-browser"}}
        """#
        return try GitHubClient.decoder().decode(GitHubNotification.self, from: Data(json.utf8))
    }
}

private actor FetchCounter {
    private var counts: [URL: Int] = [:]

    func record(_ url: URL) {
        counts[url, default: 0] += 1
    }

    func count(_ url: URL) -> Int {
        counts[url, default: 0]
    }
}
