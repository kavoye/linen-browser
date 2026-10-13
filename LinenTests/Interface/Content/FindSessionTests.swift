// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// Find-in-page state: one session per tab, carrying the match arithmetic
/// WebKit's find API doesn't provide.
@MainActor
struct FindSessionTests {
    /// A page of plain text standing in for WebKit: finds report whether the
    /// query occurs, counts count occurrences.
    private static func driver(over text: String) -> FindDriver {
        let haystack = text.lowercased()
        return FindDriver(
            find: { query, _, completion in
                completion(!query.isEmpty && haystack.contains(query.lowercased()))
            },
            countMatches: { query, completion in
                let needle = query.lowercased()
                completion(needle.isEmpty ? 0 : haystack.components(separatedBy: needle).count - 1)
            },
            clearHighlight: {}
        )
    }

    /// The regression, stated as the user saw it: find opened on one tab must
    /// not show, or leave its state, on another.
    @Test(.boundedWebViews) func eachTabKeepsItsOwnFindSession() {
        let a = BrowserTab()
        let b = BrowserTab()
        #expect(a.find !== b.find)

        a.find.driver = Self.driver(over: "needle in a needle stack")
        a.find.open()
        a.find.query = "needle"
        a.find.queryDidChange()

        #expect(a.find.isActive)
        #expect(a.find.totalMatches == 2)
        #expect(!b.find.isActive, "tab B must not inherit tab A's bar")
        #expect(b.find.query.isEmpty)
        #expect(b.find.totalMatches == 0)

        b.find.open()
        b.find.driver = Self.driver(over: "nothing here")
        b.find.query = "needle"
        b.find.queryDidChange()
        #expect(b.find.noMatches)
        #expect(a.find.totalMatches == 2, "tab B's search must not disturb tab A's counts")
        #expect(a.find.currentMatch == 1)
    }

    @Test func countsFollowTheQuery() {
        let session = FindSession()
        session.driver = Self.driver(over: "the cat sat on the mat")
        session.open()

        session.query = "the"
        session.queryDidChange()
        #expect(session.totalMatches == 2)
        #expect(session.currentMatch == 1)
        #expect(!session.noMatches)

        session.query = "dog"
        session.queryDidChange()
        #expect(session.totalMatches == 0)
        #expect(session.currentMatch == 0)
        #expect(session.noMatches)

        session.query = ""
        session.queryDidChange()
        #expect(session.totalMatches == 0)
        #expect(!session.noMatches, "an empty query is no matches, not a failure")
    }

    @Test func steppingWrapsBothWays() {
        let session = FindSession()
        session.driver = Self.driver(over: "a a a")
        session.open()
        session.query = "a"
        session.queryDidChange()
        #expect(session.totalMatches == 3)
        #expect(session.currentMatch == 1)

        session.find()
        #expect(session.currentMatch == 2)
        session.find()
        #expect(session.currentMatch == 3)
        session.find()
        #expect(session.currentMatch == 1, "past the last match wraps to the first")

        session.find(backwards: true)
        #expect(session.currentMatch == 3, "before the first match wraps to the last")
        session.find(backwards: true)
        #expect(session.currentMatch == 2)
    }

    @Test func aNewDocumentClosesTheSession() {
        let session = FindSession()
        session.driver = Self.driver(over: "word")
        session.open()
        session.query = "word"
        session.queryDidChange()
        #expect(session.totalMatches == 1)

        session.pageChanged()
        #expect(!session.isActive)
        #expect(session.query.isEmpty)
        #expect(session.totalMatches == 0)
        #expect(session.currentMatch == 0)
        #expect(!session.noMatches)
    }

    /// Through the real tab: a committed navigation takes the bar with the
    /// document it was searching.
    @Test(.boundedWebViews) func navigatingATabClosesItsFindBar() async {
        let tab = BrowserTab(opensBlank: false)
        tab.find.open()
        tab.find.query = "anything"
        #expect(tab.find.isActive)

        tab.loadHTML(
            "<!doctype html><html><body><p>fresh page</p></body></html>",
            baseURL: URL(string: "https://example.test/find")
        )
        var closed = false
        closed = await waitUntil { !tab.find.isActive }
        #expect(closed, "a committed navigation must close the find bar")
        #expect(tab.find.query.isEmpty)
    }

    /// The count script embeds the query as data; quotes and backslashes must
    /// not escape into the page's script.
    @Test func countScriptEscapesTheQuery() {
        let script = FindSession.countScript(for: #"a "quoted" \ query"#)
        #expect(script.contains(#"["a \"quoted\" \\ query"]"#))
    }

    @Test func stepArithmeticCoversTheEdges() {
        #expect(FindSession.step(from: 0, of: 0, backwards: false) == 0)
        #expect(FindSession.step(from: 0, of: 5, backwards: false) == 1)
        #expect(FindSession.step(from: 0, of: 5, backwards: true) == 5)
        #expect(FindSession.step(from: 5, of: 5, backwards: false) == 1)
        #expect(FindSession.step(from: 1, of: 5, backwards: true) == 5)
        #expect(FindSession.step(from: 3, of: 5, backwards: false) == 4)
        #expect(FindSession.step(from: 3, of: 5, backwards: true) == 2)
    }
}
