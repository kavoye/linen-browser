// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Synchronization
import Testing

@testable import Linen

@MainActor
struct GitHubPanelTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: TestDefaults.name("GitHubPanelTests"))!
    }

    @Test func filterQuerySplitsStateAndSortAndRoundTrips() {
        let parts = GitHubFilterQuery("is:open involves:@me label:bug sort:updated-desc")
        #expect(parts == GitHubFilterQuery(state: .open, sort: .updated, qualifiers: "involves:@me label:bug"))
        #expect(parts.query == "is:open involves:@me label:bug sort:updated-desc")
        let unknown = GitHubFilterQuery("is:unmerged author:@me sort:updated-desc sort:created-asc")
        #expect(unknown == GitHubFilterQuery(state: .all, sort: .bestMatch, qualifiers: "is:unmerged author:@me sort:updated-desc sort:created-asc"))
        #expect(unknown.query == "is:unmerged author:@me sort:updated-desc sort:created-asc")
        let typed = GitHubFilterQuery(state: .closed, sort: .newest, qualifiers: "is:open sort:updated-desc repo:a/b")
        #expect(typed.query == "is:closed repo:a/b sort:created-desc")
    }

    @Test func filterSearchGroupsAlternativesAndKeepsSortOutside() {
        #expect(GitHubFilterQuery("is:open label:a OR label:b sort:updated-desc").searchQuery
            == "is:pr is:open (label:a OR label:b) sort:updated-desc")
        #expect(GitHubFilterQuery("draft:true author:@me").searchQuery == "is:pr draft:true author:@me")
        #expect(GitHubFilterQuery("is:merged").state == .merged)
        #expect(GitHubFilterQuery("repo:a/b sort:reactions-desc").searchQuery == "is:pr repo:a/b sort:reactions-desc")
        #expect(GitHubFilter(id: "x", name: "x", query: "is:open assignee:@me").searchQuery(login: "octocat")
            == "is:pr is:open assignee:octocat")
    }

    @Test func onlyAnAtMeQualifierValueBecomesTheLogin() {
        let filter = GitHubFilter(id: "x", name: "x", query: #"is:open "@mentions" label:@merge-queue -author:@me assignee:@me OR involves:@me"#)
        #expect(filter.searchQuery(login: "octocat")
            == #"is:pr is:open ("@mentions" label:@merge-queue -author:octocat assignee:octocat OR involves:octocat)"#)
    }

    @Test func untrustedLinksOpenOnlyWebPages() throws {
        let coordinator = AppCoordinator()
        let before = coordinator.browser.tabs.count
        for link in ["file:///Users/me/.ssh/config", "linen://settings", "docs/README.md", "javascript:alert(1)"] {
            coordinator.openGitHubLink(try #require(URL(string: link)))
        }
        #expect(coordinator.browser.tabs.count == before)
        coordinator.openGitHubLink(try #require(URL(string: "https://example.com/guide")))
        #expect(coordinator.browser.tabs.count == before + 1)
    }

    @Test func savedFilterKeepsItsSymbol() {
        let settings = defaults()
        let id = UUID()
        GitHubPanelModel(profileID: id, defaults: settings)
            .saveFilter(GitHubFilter(id: "custom", name: "Bugs", query: "label:bug", symbol: "ladybug"))
        let restored = GitHubPanelModel(profileID: id, defaults: settings)
        #expect(restored.filters.first { $0.id == "custom" }?.symbolName == "ladybug")
        #expect(restored.filters.first { $0.id == "review" }?.symbolName == "eye")
    }

    @Test func filtersPersistPerProfileAndResolveCurrentAccount() {
        let settings = defaults()
        let id = UUID()
        let model = GitHubPanelModel(profileID: id, defaults: settings)
        model.saveFilter(GitHubFilter(id: "custom", name: "Needs me", query: "is:open commenter:@me label:bug"))
        let restored = GitHubPanelModel(profileID: id, defaults: settings)
        #expect(restored.selectedFilterID == "custom")
        #expect(restored.selectedFilter.searchQuery(login: "octocat") == "is:pr is:open commenter:octocat label:bug")
        #expect(restored.filters.contains { $0.id == "assigned" })
        #expect(restored.filters.contains { $0.id == "review" })
        let privateModel = GitHubPanelModel(profileID: id, isPrivate: true, defaults: settings)
        #expect(!privateModel.filters.contains { $0.id == "custom" })
        privateModel.saveFilter(GitHubFilter(id: "private", name: "Private", query: "is:open"))
        #expect(!GitHubPanelModel(profileID: id, defaults: settings).filters.contains { $0.id == "private" })
    }

    @Test func credentialsAreScopedToTheirProfile() throws {
        let box = GitHubTestCredentials()
        let first = GitHubConnectionStore(profileID: UUID(), storage: box.storage)
        let second = GitHubConnectionStore(profileID: UUID(), storage: box.storage)
        try first.save("test-credential")
        #expect(first.read() != nil)
        #expect(second.read() == nil)
        try first.save(nil)
        #expect(first.read() == nil)
    }

    @Test func backgroundRefreshDoesNotRequireABrowserTab() async throws {
        let box = GitHubTestCredentials()
        let id = UUID()
        try GitHubConnectionStore(profileID: id, storage: box.storage).save("test-credential")
        let client = GitHubClient { request in
            let path = request.url!.path
            let json: String
            if path == "/user" {
                json = #"{"login":"octocat"}"#
            } else if path == "/graphql" {
                json = #"{"data":{"search":{"issueCount":0,"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}"#
            } else {
                json = "[]"
            }
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let model = GitHubPanelModel(profileID: id, defaults: defaults(), client: client, storage: box.storage)
        model.start()
        #expect(await waitUntil { model.lastUpdated != nil })
        #expect(model.account?.login == "octocat")
        #expect(model.errorMessage == nil)
        #expect(model.hasConnection)
        model.disconnect()
        #expect(!model.hasConnection)
        #expect(model.account == nil)
        #expect(model.lastUpdated == nil)
        #expect(GitHubConnectionStore(profileID: id, storage: box.storage).read() == nil)
    }

    private nonisolated static func pullRequest(_ number: Int) -> String {
        GitHubFixtures.pullRequestJSON(state: "OPEN", checks: "SUCCESS", review: nil)
            .replacingOccurrences(of: "PR_42", with: "PR_\(number)")
            .replacingOccurrences(of: #""number":42"#, with: #""number":\#(number)"#)
            .replacingOccurrences(of: "/pull/42", with: "/pull/\(number)")
    }

    private func connectedModel(
        log: GitHubRequestLog, pause: @escaping @Sendable (String) async -> Void = { _ in },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        respond: @escaping @Sendable (String, URLRequest) -> String?
    ) throws -> GitHubPanelModel {
        let box = GitHubTestCredentials()
        let id = UUID()
        try GitHubConnectionStore(profileID: id, storage: box.storage).save("test-credential")
        let client = GitHubClient { request in
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            let kind = switch request.url!.path {
            case "/user":
                "user"
            case "/notifications":
                "notifications"
            default:
                body.contains("LinenInbox(") ? "triage" : body.contains("LinenPullRequests(") ? "search"
                    : body.contains("LinenPullRequestDetails(") ? "details" : "single"
            }
            log.append(kind, request)
            await pause(kind)
            let fallback = switch kind {
            case "user":
                #"{"login":"octocat"}"#
            case "notifications":
                "[]"
            case "triage":
                #"{"data":{"review":{"nodes":[]},"authored":{"nodes":[]},"recent":{"nodes":[]}}}"#
            case "details":
                GitHubFixtures.details
            default:
                #"{"data":{"search":{"issueCount":0,"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}"#
            }
            let json = respond(kind, request) ?? fallback
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        return GitHubPanelModel(profileID: id, defaults: defaults(), client: client, storage: box.storage, sleep: sleep)
    }

    @Test func pollingKeepsPagesTheUserLoaded() async throws {
        let log = GitHubRequestLog()
        let model = try connectedModel(log: log) { kind, request in
            guard kind == "search" else { return nil }
            let more = String(decoding: request.httpBody!, as: UTF8.self).contains(#""cursor":"c1""#)
            let node = Self.pullRequest(more ? 2 : 1)
            let info = more ? #"{"hasNextPage":false,"endCursor":null}"# : #"{"hasNextPage":true,"endCursor":"c1"}"#
            return #"{"data":{"search":{"issueCount":2,"nodes":["# + node + #"],"pageInfo":"# + info + "}}}"
        }
        model.saveFilter(GitHubFilter(id: "custom", name: "Mine", query: "is:open"))
        model.panelDidAppear()
        model.start()
        #expect(await waitUntil { model.pullRequests.count == 1 && !model.isRefreshing })
        model.loadMore(notifications: false)
        #expect(await waitUntil { model.pullRequests.count == 2 && !model.isLoadingMore })
        model.refresh()
        #expect(await waitUntil { log.count("search") == 3 && !model.isRefreshing })
        #expect(model.pullRequests.map(\.number) == [1, 2])
        #expect(model.nextCursor == nil)
        model.stop()
    }

    @Test func hiddenPollsSkipTheInboxQueryAndAskOnlyForNewNotifications() async throws {
        let log = GitHubRequestLog()
        let model = try connectedModel(log: log) { _, _ in nil }
        model.start()
        #expect(await waitUntil { model.lastUpdated != nil && !model.isRefreshing })
        #expect(log.count("triage") == 1)
        model.refresh()
        #expect(await waitUntil { log.count("notifications") == 2 && !model.isRefreshing })
        #expect(log.count("triage") == 1)
        #expect(log.count("search") == 1)
        model.stop()
    }

    @Test func previewsReuseAFreshInboxPullRequest() async throws {
        let log = GitHubRequestLog()
        let model = try connectedModel(log: log) { kind, _ in
            kind == "triage" ? #"{"data":{"review":{"nodes":["# + Self.pullRequest(42) + #"]},"authored":{"nodes":[]},"recent":{"nodes":[]}}}"# : nil
        }
        model.start()
        #expect(await waitUntil { model.lastUpdated != nil && !model.isRefreshing })
        let reference = try #require(GitHubPullRequestReference(url: URL(string: "https://github.com/kavoye/linen-browser/pull/42")))
        await model.refreshPreview(reference)
        await model.refreshPreview(reference)
        let preview = await model.preview(reference)
        #expect(preview?.details != nil)
        #expect(log.count("single") == 0)
        #expect(log.count("details") == 1)
        model.stop()
    }

    @Test func aFailedPaletteSearchIsRetriedNotCached() async throws {
        let log = GitHubRequestLog()
        let fails = Mutex(true)
        let model = try connectedModel(log: log) { _, request in
            guard String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("LinenPaletteSearch(") else { return nil }
            if fails.withLock({ $0 }) {
                return #"{"errors":[{"message":"Something went wrong"}]}"#
            }
            return #"{"data":{"mine":{"nodes":[]},"scoped":{"nodes":[]},"repos":{"nodes":[{"nameWithOwner":"kavoye/linen-browser","description":null,"isPrivate":false,"url":"https://github.com/kavoye/linen-browser"}]}}}"#
        }
        model.start()
        #expect(await waitUntil { model.lastUpdated != nil && !model.isRefreshing })
        let search = GitHubPaletteSearch()
        search.update("linen", model: model)
        #expect(await waitUntil { log.count("single") == 1 })
        #expect(await waitUntil { search.hitsQuery == "linen" })
        #expect(search.hits.isEmpty)

        fails.withLock { $0 = false }
        search.update("linen", model: model)
        #expect(await waitUntil { !search.hits.isEmpty })
        #expect(search.hits.map(\.title) == ["kavoye/linen-browser"])
        model.stop()
    }

    @Test func aRateLimitedPaletteSearchBacksOff() async throws {
        let log = GitHubRequestLog()
        let model = try connectedModel(log: log) { _, request in
            guard String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("LinenPaletteSearch(") else { return nil }
            return #"{"errors":[{"type":"RATE_LIMITED","message":"API rate limit exceeded"}]}"#
        }
        model.start()
        #expect(await waitUntil { model.lastUpdated != nil && !model.isRefreshing })
        #expect(await model.paletteSearch("linen") == nil)
        #expect(model.retryAfter.map { $0 > .now } == true)
        #expect(await model.paletteSearch("linen") == nil)
        #expect(log.count("single") == 1)
        model.stop()
    }

    @Test func aThreadPreviewFailsInsteadOfLoadingForeverWhileThrottled() async throws {
        let log = GitHubRequestLog()
        let model = try connectedModel(log: log) { _, request in
            guard String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("LinenPaletteSearch(") else { return nil }
            return #"{"errors":[{"type":"RATE_LIMITED","message":"API rate limit exceeded"}]}"#
        }
        model.start()
        #expect(await waitUntil { model.lastUpdated != nil && !model.isRefreshing })
        _ = await model.paletteSearch("linen")
        let json = #"""
        {"id":"7","unread":true,"reason":"mention","updated_at":"2026-10-06T10:07:00Z",
         "subject":{"title":"Thread 3","type":"Issue","url":"https://api.github.com/repos/kavoye/linen-browser/issues/3"},
         "repository":{"full_name":"kavoye/linen-browser"}}
        """#
        let notification = try GitHubClient.decoder().decode(GitHubNotification.self, from: Data(json.utf8))
        let item = GitHubInboxItem(id: "n-7", reason: .mentioned, pr: nil, notification: notification)
        model.loadPreview(for: item)
        #expect(model.thread(for: item) == .failed)
        model.stop()
    }

    @Test func aRefreshKeepsARateLimitSetWhileItRan() async throws {
        let log = GitHubRequestLog()
        let slow = Mutex(false)
        let model = try connectedModel(log: log, pause: { kind in
            if kind == "notifications", slow.withLock({ $0 }) {
                try? await Task.sleep(for: .milliseconds(300))
            }
        }) { _, request in
            guard String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("LinenPaletteSearch(") else { return nil }
            return #"{"errors":[{"type":"RATE_LIMITED","message":"API rate limit exceeded"}]}"#
        }
        model.start()
        #expect(await waitUntil { model.lastUpdated != nil && !model.isRefreshing })
        slow.withLock { $0 = true }
        model.refresh()
        #expect(model.isRefreshing)
        _ = await model.paletteSearch("linen")
        #expect(model.isRefreshing)
        #expect(await waitUntil { !model.isRefreshing })
        #expect(model.retryAfter.map { $0 > .now } == true)
        model.stop()
    }

    @Test func theRateLimitEndsOnItsOwnWithoutAnotherRequest() async throws {
        let log = GitHubRequestLog()
        let model = try connectedModel(log: log, sleep: { duration in
            guard duration >= .seconds(60) else { return }
            try await Task.sleep(for: .seconds(3600))
        }) { _, request in
            guard String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("LinenPaletteSearch(") else { return nil }
            return #"{"errors":[{"type":"RATE_LIMITED","message":"API rate limit exceeded"}]}"#
        }
        model.start()
        #expect(await waitUntil { model.lastUpdated != nil && !model.isRefreshing })
        _ = await model.paletteSearch("linen")
        #expect(await waitUntil { !model.isRateLimited })
        #expect(model.retryAfter == nil)
        model.stop()
    }

    @Test func theNotificationSettingIsABindableProperty() {
        let settings = defaults()
        let id = UUID()
        let model = GitHubPanelModel(profileID: id, defaults: settings)
        model.notifiesAboutPullRequests = false
        #expect(!model.notifiesAboutPullRequests)
        #expect(!GitHubPanelModel(profileID: id, defaults: settings).notifiesAboutPullRequests)
        let privateModel = GitHubPanelModel(profileID: id, isPrivate: true, defaults: settings)
        privateModel.notifiesAboutPullRequests = true
        #expect(!privateModel.notifiesAboutPullRequests)
    }

    @Test func oneRateLimitedRefreshCountsAsOneStrike() async throws {
        let log = GitHubRequestLog()
        let model = try connectedModel(log: log) { kind, _ in
            ["triage", "search"].contains(kind) ? #"{"errors":[{"type":"RATE_LIMITED","message":"API rate limit exceeded"}]}"# : nil
        }
        model.saveFilter(GitHubFilter(id: "custom", name: "Mine", query: "is:open"))
        model.panelDidAppear()
        model.start()
        #expect(await waitUntil { log.count("triage") == 1 && log.count("search") == 1 && !model.isRefreshing })
        let wait = try #require(model.retryAfter).timeIntervalSinceNow
        #expect(wait > 50 && wait < 90)
        model.stop()
    }

    @Test func loadingMoreAfterMarkingThreadsReadSkipsNone() async throws {
        let box = GitHubTestCredentials()
        let id = UUID()
        try GitHubConnectionStore(profileID: id, storage: box.storage).save("test-credential")
        let newest = Date(timeIntervalSince1970: 1_791_000_000)
        let read = Mutex<Set<Int>>([])
        let client = GitHubClient { request in
            let url = request.url!
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            var status = 200
            var headers: [String: String] = [:]
            let json: String
            if url.path == "/user" {
                json = #"{"login":"octocat"}"#
            } else if url.path.hasPrefix("/notifications/threads/") {
                read.withLock { _ = $0.insert(Int(url.lastPathComponent)!) }
                (json, status) = ("", 205)
            } else if url.path == "/notifications" {
                let before = query.first { $0.name == "before" }?.value.flatMap { try? Date($0, strategy: .iso8601) }
                let page = query.first { $0.name == "page" }?.value.flatMap(Int.init) ?? 1
                let unread = (1...60).filter { number in
                    !read.withLock { $0.contains(number) }
                        && before.map { newest.addingTimeInterval(-Double(number) * 60) < $0 } ?? true
                }
                let slice = unread.dropFirst((page - 1) * 50).prefix(50)
                if unread.count > page * 50 {
                    headers["Link"] = #"<https://api.github.com/notifications?page=2>; rel="next""#
                }
                json = "[" + slice.map { number in
                    let updated = newest.addingTimeInterval(-Double(number) * 60).formatted(.iso8601)
                    return #"""
                    {"id":"\#(number)","unread":true,"reason":"mention","updated_at":"\#(updated)",
                     "subject":{"title":"Thread \#(number)","type":"Issue","url":"https://api.github.com/repos/kavoye/linen-browser/issues/\#(number)"},
                     "repository":{"full_name":"kavoye/linen-browser"}}
                    """#
                }.joined(separator: ",") + "]"
            } else {
                json = #"{"data":{"review":{"nodes":[]},"authored":{"nodes":[]},"recent":{"nodes":[]}}}"#
            }
            return (Data(json.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!)
        }
        let model = GitHubPanelModel(profileID: id, defaults: defaults(), client: client, storage: box.storage)
        model.start()
        #expect(await waitUntil { model.notifications.count == 50 && !model.isRefreshing })
        for notification in model.notifications.prefix(5) {
            model.markRead(notification)
        }
        #expect(await waitUntil { model.notifications.count == 45 && model.markingRead.isEmpty })
        model.loadMore(notifications: true)
        #expect(await waitUntil { !model.isLoadingMore && model.notifications.count > 45 })
        #expect(Set(model.notifications.map(\.id)) == Set((6...60).map(String.init)))
        #expect(!model.hasMoreNotifications)
        model.stop()
    }

    @Test func aMarkReadFromAnEarlierConnectionLeavesTheCurrentOneMarking() async throws {
        let box = GitHubTestCredentials()
        let id = UUID()
        try GitHubConnectionStore(profileID: id, storage: box.storage).save("test-credential")
        let calls = Mutex(0)
        let released = Mutex<Set<Int>>([])
        let client = GitHubClient { request in
            let url = request.url!
            let json: String
            var status = 200
            if url.path == "/user" {
                json = #"{"login":"octocat"}"#
            } else if url.path.hasPrefix("/notifications/threads/") {
                let call = calls.withLock { $0 += 1; return $0 }
                while !released.withLock({ $0.contains(call) }) {
                    try await Task.sleep(for: .milliseconds(10))
                }
                (json, status) = ("", 205)
            } else if url.path == "/notifications" {
                json = #"""
                [{"id":"7","unread":true,"reason":"mention","updated_at":"2026-10-01T12:00:00Z",
                  "subject":{"title":"Thread 7","type":"Issue","url":"https://api.github.com/repos/kavoye/linen-browser/issues/7"},
                  "repository":{"full_name":"kavoye/linen-browser"}}]
                """#
            } else {
                json = #"{"data":{"review":{"nodes":[]},"authored":{"nodes":[]},"recent":{"nodes":[]}}}"#
            }
            return (Data(json.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        let model = GitHubPanelModel(profileID: id, defaults: defaults(), client: client, storage: box.storage)
        model.start()
        #expect(await waitUntil { model.notifications.count == 1 && !model.isRefreshing })
        model.markRead(model.notifications[0])
        #expect(await waitUntil { calls.withLock { $0 } == 1 })
        model.stop()
        model.start()
        #expect(await waitUntil { model.notifications.count == 1 && !model.isRefreshing })
        model.markRead(model.notifications[0])
        #expect(await waitUntil { calls.withLock { $0 } == 2 })
        released.withLock { _ = $0.insert(1) }
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.markingRead == ["7"])
        released.withLock { _ = $0.insert(2) }
        #expect(await waitUntil { model.markingRead.isEmpty && model.notifications.isEmpty })
        model.stop()
    }

    @Test func anAbandonedSignInKeepsDetailsLoadingOnTheCurrentConnection() async throws {
        let box = GitHubTestCredentials()
        let id = UUID()
        try GitHubConnectionStore(profileID: id, storage: box.storage).save("test-credential")
        let client = GitHubClient { request in
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            let json: String
            if request.url!.path == "/user" {
                json = #"{"login":"octocat"}"#
            } else if body.contains("LinenPullRequestDetails(") {
                try await Task.sleep(for: .milliseconds(300))
                json = GitHubFixtures.details
            } else if request.url!.path == "/graphql" {
                json = #"{"data":{"review":{"nodes":[]},"authored":{"nodes":[]},"recent":{"nodes":[]}}}"#
            } else {
                json = "[]"
            }
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let model = GitHubPanelModel(
            profileID: id, defaults: defaults(), client: client,
            authorization: GitHubAuthorization(clientID: ""), storage: box.storage
        )
        model.start()
        #expect(await waitUntil { model.lastUpdated != nil && !model.isRefreshing })
        let pr = try GitHubFixtures.pullRequest(state: "OPEN", checks: "SUCCESS", review: nil)
        model.loadDetails(for: pr)
        #expect(model.loadingDetails.contains(pr.id))
        model.connect(includePrivate: false) { _ in }
        #expect(await waitUntil { !model.isConnecting && model.errorMessage != nil })
        #expect(await waitUntil { !model.loadingDetails.contains(pr.id) })
        #expect(model.details[pr.id] != nil)
        model.stop()
    }

    @Test func choosingAFilterDuringTheFirstRefreshStillLoadsTheInbox() async throws {
        let box = GitHubTestCredentials()
        let id = UUID()
        try GitHubConnectionStore(profileID: id, storage: box.storage).save("test-credential")
        let log = GitHubRequestLog()
        let client = GitHubClient { request in
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            let json: String
            if request.url!.path == "/user" {
                json = #"{"login":"octocat"}"#
            } else if body.contains("LinenInbox(") {
                log.append("triage", request)
                try await Task.sleep(for: .milliseconds(300))
                json = #"{"data":{"review":{"nodes":["# + Self.pullRequest(42) + #"]},"authored":{"nodes":[]},"recent":{"nodes":[]}}}"#
            } else if request.url!.path == "/graphql" {
                json = #"{"data":{"search":{"issueCount":0,"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}"#
            } else {
                json = "[]"
            }
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let model = GitHubPanelModel(profileID: id, defaults: defaults(), client: client, storage: box.storage)
        model.start()
        #expect(await waitUntil { log.count("triage") == 1 })
        model.saveFilter(GitHubFilter(id: "custom", name: "Mine", query: "is:open"))
        #expect(await waitUntil { !model.isRefreshing })
        #expect(model.triage.reviewRequested.map(\.number) == [42])
        #expect(model.errorMessage == nil)
        model.stop()
    }

    @Test func signingInCountsAsStarted() async throws {
        let box = GitHubTestCredentials()
        let id = UUID()
        let log = GitHubRequestLog()
        let client = GitHubClient { request in
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            let kind = request.url!.path == "/user" ? "user" : body.contains("LinenInbox(") ? "triage" : "other"
            log.append(kind, request)
            let json = switch kind {
            case "user":
                #"{"login":"octocat"}"#
            case "triage":
                #"{"data":{"review":{"nodes":[]},"authored":{"nodes":[]},"recent":{"nodes":[]}}}"#
            default:
                "[]"
            }
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let authorization = GitHubAuthorization(clientID: "client") { request in
            let json = request.url!.path == "/login/device/code"
                ? #"{"device_code":"device","user_code":"ABCD-EFGH","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#
                : #"{"access_token":"test-credential"}"#
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let model = GitHubPanelModel(
            profileID: id, defaults: defaults(), client: client, authorization: authorization, storage: box.storage,
            sleep: { duration in
                if duration > .seconds(10) {
                    try await Task.sleep(for: .seconds(3600))
                }
            }
        )
        model.connect(includePrivate: false) { _ in }
        #expect(await waitUntil { model.lastUpdated != nil && !model.isRefreshing })
        #expect(log.count("triage") == 1)
        model.start()
        #expect(!model.isRefreshing)
        #expect(log.count("triage") == 1)
        model.stop()
    }

    @Test func privateWindowsNeverReadStoredConnection() throws {
        let box = GitHubTestCredentials()
        let id = UUID()
        try GitHubConnectionStore(profileID: id, storage: box.storage).save("test-credential")
        let model = GitHubPanelModel(profileID: id, isPrivate: true, defaults: defaults(), storage: box.storage)
        model.start()
        #expect(!model.hasConnection)
        #expect(!model.isRefreshing)
    }

    @Test func rateLimitPreventsImmediateRetry() async throws {
        let client = GitHubClient { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil,
                                      headerFields: ["X-RateLimit-Remaining": "0", "Retry-After": "120"])!)
        }
        do {
            _ = try await client.account(token: "test")
            Issue.record("Expected rate limit")
        } catch GitHubFailure.rateLimited(let until) {
            #expect(until.timeIntervalSinceNow > 110)
        }
    }

    @Test func deviceFlowRequestsConsentWithoutAClientSecret() async throws {
        let auth = GitHubAuthorization(clientID: "public-client-id") { request in
            let body = String(decoding: request.httpBody!, as: UTF8.self)
            #expect(body.contains("client_id=public%2Dclient%2Did"))
            #expect(body.contains("notifications"))
            #expect(body.contains("read%3Aorg") || body.contains("read:org"))
            #expect(!body.contains("client_secret"))
            #expect(!body.contains("repo"))
            let json = #"{"device_code":"device","user_code":"ABCD-EFGH","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let code = try await auth.begin(includePrivate: false)
        #expect(code.userCode == "ABCD-EFGH")
        #expect(code.interval == 5)
    }

    @Test func deviceFlowKeepsPollingThroughATransientFailure() async throws {
        let attempts = Mutex(0)
        let auth = GitHubAuthorization(clientID: "client") { request in
            let attempt = attempts.withLock { $0 += 1; return $0 }
            if attempt == 1 {
                throw URLError(.timedOut)
            }
            return (Data("<html>".utf8), HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!)
        }
        let code = GitHubDeviceCode(deviceCode: "device", userCode: "code", verificationUri: URL(string: "https://github.com/login/device")!, expiresIn: 900, interval: 5)
        guard case .pending = try await auth.poll(code) else { Issue.record("A timeout ends sign-in"); return }
        guard case .pending = try await auth.poll(code) else { Issue.record("A server error ends sign-in"); return }
    }

    @Test(arguments: ["authorization_pending", "slow_down", "expired_token", "access_denied"])
    func deviceFlowHandlesGitHubPollingStates(state: String) async throws {
        let auth = GitHubAuthorization(clientID: "client") { request in
            let data = try JSONSerialization.data(withJSONObject: ["error": state])
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let code = GitHubDeviceCode(deviceCode: "device", userCode: "code", verificationUri: URL(string: "https://github.com/login/device")!, expiresIn: 900, interval: 5)
        do {
            let result = try await auth.poll(code)
            switch result {
            case .pending:
                #expect(state == "authorization_pending")
            case .slowDown:
                #expect(state == "slow_down")
            case .authorized:
                Issue.record("Unexpected authorization")
            }
        } catch GitHubFailure.expired {
            #expect(state == "expired_token")
        } catch GitHubFailure.denied {
            #expect(state == "access_denied")
        }
    }
}

nonisolated final class GitHubTestCredentials: Sendable {
    private let values = Mutex<[String: String]>([:])
    var storage: CredentialStore.Storage {
        CredentialStore.Storage(
            read: { [self] key in values.withLock { $0[key] } },
            write: { [self] value, key in values.withLock { $0[key] = value }; return 0 },
            delete: { [self] key in values.withLock { $0[key] = nil }; return 0 }
        )
    }
}

nonisolated final class GitHubRequestLog: Sendable {
    private let kinds = Mutex<[String]>([])

    func append(_ kind: String, _ request: URLRequest) {
        kinds.withLock { $0.append(kind) }
    }

    func count(_ kind: String) -> Int {
        kinds.withLock { $0.filter { $0 == kind }.count }
    }
}
