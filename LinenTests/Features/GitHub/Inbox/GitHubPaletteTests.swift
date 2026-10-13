// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@MainActor
struct GitHubPaletteTests {
    @Test func routesNumbersRepositoriesAndText() {
        #expect(GitHubPaletteRoute.of("  ", context: nil) == .empty)
        #expect(GitHubPaletteRoute.of("#42", context: "kavoye/linen-browser") == .number(repository: "kavoye/linen-browser", number: 42))
        #expect(GitHubPaletteRoute.of("42", context: "kavoye/linen-browser") == .number(repository: "kavoye/linen-browser", number: 42))
        #expect(GitHubPaletteRoute.of("#42", context: nil) == .search("#42"))
        #expect(GitHubPaletteRoute.of("apple/swift#7", context: nil) == .number(repository: "apple/swift", number: 7))
        #expect(GitHubPaletteRoute.of("apple/swift", context: nil) == .repository("apple/swift"))
        #expect(GitHubPaletteRoute.of("../etc", context: nil) == .search("../etc"))
        #expect(GitHubPaletteRoute.of("keyboard shortcuts", context: nil) == .search("keyboard shortcuts"))
    }

    @Test func findsTheRepositoryOfAPage() {
        #expect(GitHubPaletteRoute.repository(of: URL(string: "https://github.com/kavoye/linen-browser/pull/2/files")) == "kavoye/linen-browser")
        #expect(GitHubPaletteRoute.repository(of: URL(string: "https://github.com/notifications/beta")) == nil)
        #expect(GitHubPaletteRoute.repository(of: URL(string: "https://github.com/kavoye")) == nil)
        #expect(GitHubPaletteRoute.repository(of: URL(string: "https://example.com/kavoye/linen")) == nil)
    }

    @Test func emptyQueryOffersTheCurrentRepositoryYourPullRequestsAndRepositories() throws {
        let pr = try GitHubFixtures.pullRequest(state: "OPEN", checks: "SUCCESS", review: "APPROVED")
        let sections = GitHubPaletteSections.build(
            query: "", webItem: nil, context: "kavoye/linen-browser",
            known: ["kavoye/linen-browser", "apple/swift"], mine: [pr], hits: [], hitsQuery: "", actions: Self.actions()
        )
        #expect(sections.map(\.id) == ["github-pages", "github-mine", "github-repos"])
        #expect(sections[0].items.count == GitHubRepositoryPage.allCases.count)
        #expect(sections[2].items.map(\.title) == ["apple/swift"])
    }

    @Test func numberJumpComesFirstAndStaleResultsStayHidden() throws {
        let opened = Box<URL>()
        let sections = GitHubPaletteSections.build(
            query: "#42", webItem: Self.webItem("#42"), context: "kavoye/linen-browser",
            known: [], mine: [], hits: [try Self.issueHit()], hitsQuery: "keyboard", actions: Self.actions(open: opened)
        )
        #expect(sections.map(\.id) == ["github-number", "site-search"])
        sections[0].items[0].run()
        #expect(opened.value?.absoluteString == "https://github.com/kavoye/linen-browser/issues/42")
    }

    @Test func searchShowsWorkAndRepositoriesAndSplitsLinkedItems() throws {
        let split = Box<(URL, URL)>()
        let hits = [
            try Self.issueHit(),
            GitHubSearchHit(kind: .repository(description: "A browser", isPrivate: true), title: "kavoye/linen-browser",
                            number: nil, repository: "kavoye/linen-browser", url: URL(string: "https://github.com/kavoye/linen-browser")!),
        ]
        let sections = GitHubPaletteSections.build(
            query: "linen", webItem: Self.webItem("linen"), context: nil,
            known: ["kavoye/linen-browser", "apple/swift"], mine: [], hits: hits, hitsQuery: "linen",
            actions: Self.actions(split: split)
        )
        #expect(sections.map(\.id) == ["site-search", "github-work", "github-repos"])
        #expect(sections[2].items.map(\.title) == ["kavoye/linen-browser"])
        let issue = sections[1].items[0]
        #expect(issue.detail == "kavoye/linen-browser #38 · Open")
        issue.alternate?()
        #expect(split.value?.0.absoluteString == "https://github.com/kavoye/linen-browser/issues/38")
        #expect(split.value?.1.absoluteString == "https://github.com/kavoye/linen-browser/pull/42")
    }

    @Test func clientSearchesScopedWorkAndDecodesMixedResults() async throws {
        let queries = GitHubClient.paletteQueries("keyboard", login: "octocat", repositories: ["kavoye/linen-browser", "bad repo"])
        #expect(queries["scoped"] == "keyboard archived:false sort:updated-desc user:octocat repo:kavoye/linen-browser")
        #expect(queries["mine"] == "keyboard involves:octocat sort:updated-desc")
        #expect(queries["repos"] == "keyboard in:name")

        let pr = GitHubFixtures.pullRequestJSON(state: "OPEN", checks: "SUCCESS", review: "APPROVED")
            .replacingOccurrences(of: #"{"id":"PR_42""#, with: #"{"kind":"PullRequest","closingIssuesReferences":{"nodes":[{"url":"https://github.com/kavoye/linen-browser/issues/38"}]},"id":"PR_42""#)
        let json = #"""
        {"data":{
          "mine":{"nodes":[\#(pr),{"kind":"Issue","number":38,"title":"Shortcuts in Peek","url":"https://github.com/kavoye/linen-browser/issues/38",
            "issueState":"OPEN","repository":{"nameWithOwner":"kavoye/linen-browser"},"closedByPullRequestsReferences":{"nodes":[]}}]},
          "scoped":{"nodes":[\#(pr),{"kind":"Issue","number":9,"title":"Spoofed","url":"https://evil.test/x","issueState":"OPEN","repository":{"nameWithOwner":"a/b"}}]},
          "repos":{"nodes":[{"nameWithOwner":"kavoye/linen-browser","description":null,"isPrivate":true,"url":"https://github.com/kavoye/linen-browser"},{}]}
        }}
        """#
        let client = GitHubClient { request in
            let query = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
            let issue = (query?["query"] as? String)?.firstMatch(of: /\.\.\. on Issue \{[^}]*/).map { String($0.0) } ?? ""
            #expect(issue.contains("issueState: state"))
            #expect(issue.firstMatch(of: #/(^|[^:] )state /#) == nil)
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let hits = try await client.paletteSearch("keyboard", login: "octocat", repositories: [], token: "test")
        #expect(hits.map(\.number) == [42, 38, nil])
        #expect(hits[0].linked?.absoluteString == "https://github.com/kavoye/linen-browser/issues/38")
        #expect(hits[2].kind == .repository(description: nil, isPrivate: true))
    }

    private static func webItem(_ query: String) -> OmniboxItem {
        OmniboxItem(id: "site-search-github", kind: .search, title: query, run: {})
    }

    private static func issueHit() throws -> GitHubSearchHit {
        GitHubSearchHit(
            kind: .issue(state: "OPEN"), title: "Shortcuts in Peek", number: 38, repository: "kavoye/linen-browser",
            url: try #require(URL(string: "https://github.com/kavoye/linen-browser/issues/38")),
            linked: URL(string: "https://github.com/kavoye/linen-browser/pull/42")
        )
    }

    private static func actions(open: Box<URL>? = nil, split: Box<(URL, URL)>? = nil) -> GitHubPaletteActions {
        GitHubPaletteActions(
            open: { open?.value = $0 },
            openCurrent: { open?.value = $0 },
            split: { split?.value = ($0, $1) }
        )
    }
}

private final class Box<Value> {
    var value: Value?
}
