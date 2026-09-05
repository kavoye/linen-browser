// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// Both wire formats an engine can answer with, fed to the parser as raw
/// bytes: each one is a shape Linen does not control.
struct SuggestionParsingTests {
    private static func data(_ json: String) -> Data {
        Data(json.utf8)
    }

    @Test func readsDuckDuckGoPhraseRows() {
        let payload = Self.data(#"[{"phrase":"first"},{"phrase":"second"}]"#)
        #expect(SearchSuggestions.phrases(in: payload, format: .phrases) == ["first", "second"])
    }

    @Test func toleratesExtraFieldsOnAPhraseRow() {
        let payload = Self.data(#"[{"phrase":"first","score":3,"image":"x.png"}]"#)
        #expect(SearchSuggestions.phrases(in: payload, format: .phrases) == ["first"])
    }

    @Test func readsAnOpenSearchList() {
        let payload = Self.data(#"["te",["test one","test two","test three"]]"#)
        #expect(SearchSuggestions.phrases(in: payload, format: .openSearch)
            == ["test one", "test two", "test three"])
    }

    /// Google appends descriptions and metadata after the list; only the
    /// second element counts.
    @Test func ignoresOpenSearchTrailers() {
        let payload = Self.data(#"["te",["one","two"],["desc","desc"],{"google:verbatim":true}]"#)
        #expect(SearchSuggestions.phrases(in: payload, format: .openSearch) == ["one", "two"])
    }

    @Test(arguments: [
        "",
        "not json at all",
        #"{"phrase":"an object, not an array"}"#,
        #"[{"word":"wrong key"}]"#,
        #"[{"phrase":42}]"#,
        #"["te",["ok"]"#,
    ])
    func returnsNothingForAPhrasePayloadItCannotRead(_ payload: String) {
        #expect(SearchSuggestions.phrases(in: Self.data(payload), format: .phrases).isEmpty)
    }

    @Test(arguments: [
        "",
        "not json at all",
        #"{"1":["one"]}"#,
        #"["query alone"]"#,
        #"["te","not a list"]"#,
        #"["te",[1,2,3]]"#,
        #"["te",["one",2]]"#,
    ])
    func returnsNothingForAnOpenSearchPayloadItCannotRead(_ payload: String) {
        #expect(SearchSuggestions.phrases(in: Self.data(payload), format: .openSearch).isEmpty)
    }

    @Test func theTwoFormatsDoNotShareAssumptions() {
        let phrases = Self.data(#"[{"phrase":"first"}]"#)
        let openSearch = Self.data(#"["te",["one"]]"#)
        #expect(SearchSuggestions.phrases(in: phrases, format: .openSearch).isEmpty)
        #expect(SearchSuggestions.phrases(in: openSearch, format: .phrases).isEmpty)
    }
}

/// The fetch path against a loopback fixture: template expansion, the status
/// check, and the parse, with nothing leaving the machine.
struct SuggestionFetchTests {
    private static func engine(suggestTemplate: String?) -> SearchEngine {
        SearchEngine(
            id: "fixture",
            name: "Fixture",
            template: "https://example.invalid/search?q=%s",
            suggestTemplate: suggestTemplate,
            suggestionFormat: .openSearch
        )
    }

    @Test func fetchesAndParsesThroughTheEnginesTemplate() async throws {
        let payload = #"["te",["test one","test two"]]"#
        let server = try await HTTPFixtureServer.start(routes: [
            "/suggest": .bytes(Data(payload.utf8), contentType: "application/json"),
        ])
        let template = try server.url("/suggest").absoluteString + "?q=%s"
        let fetched = await SearchSuggestions.fetch("te", from: Self.engine(suggestTemplate: template))
        #expect(fetched == ["test one", "test two"])
    }

    @Test func anEngineWithoutASuggestionEndpointFetchesNothing() async {
        let fetched = await SearchSuggestions.fetch("te", from: Self.engine(suggestTemplate: nil))
        #expect(fetched.isEmpty)
    }

    @Test func aFailingEndpointProducesNoSuggestions() async throws {
        let server = try await HTTPFixtureServer.start(routes: [:])
        let template = try server.url("/missing").absoluteString + "?q=%s"
        let fetched = await SearchSuggestions.fetch("te", from: Self.engine(suggestTemplate: template))
        #expect(fetched.isEmpty)
    }

    /// `&` left raw would split the query into an extra parameter on the
    /// engine's own URL.
    @Test func escapesTheQueryIntoTheSuggestionURL() throws {
        let url = try #require(SearchEngine.duckDuckGo.suggestURL(for: "a&b c"))
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.first { $0.name == "q" }?.value == "a&b c")
    }
}

@MainActor
/// What the cache holds between keystrokes. It answers from memory as a
/// person backspaces, so it must not grow for as long as the window is open.
struct SuggestionCacheTests {
    private let engine = SearchEngine.duckDuckGo

    @Test func theOldestQuestionIsLetGoRatherThanGrowing() {
        let suggestions = SearchSuggestions()
        for index in 0..<80 {
            suggestions.store(["answer \(index)"], for: "query\(index)", engine: engine)
        }

        #expect(suggestions.cachedQueries.count == 80)
        #expect(suggestions.cachedQueries.first?.hasSuffix("query0") == true)

        suggestions.store(["answer 80"], for: "query80", engine: engine)

        #expect(suggestions.cachedQueries.count == 80)
        #expect(suggestions.cachedQueries.first?.hasSuffix("query1") == true)
        #expect(suggestions.cachedQueries.last?.hasSuffix("query80") == true)
    }

    @Test func askingTheSameQuestionTwiceIsOneEntry() {
        let suggestions = SearchSuggestions()
        suggestions.store(["one"], for: "swift", engine: engine)
        suggestions.store(["two"], for: "SWIFT", engine: engine)

        #expect(suggestions.cachedQueries.count == 1)
        #expect(suggestions.phrases == ["two"])
    }
}
