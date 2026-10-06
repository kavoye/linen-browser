// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@MainActor
struct CommandPaletteSiteSearchTests {
    @Test(arguments: ["yo", "You", "YOUTUBE", "youtube.com", "https://www.youtube.com/"])
    func matchesYouTubePrefixes(query: String) {
        #expect(SiteSearch.match(query)?.id == "youtube")
    }

    @Test(arguments: ["", "y", "youtube music", "> youtube", "@youtube", "?youtube", "youtube.com.evil.test", "youtube.com/watch?v=123"])
    func ignoresQueriesThatAreNotSiteNames(query: String) {
        #expect(SiteSearch.match(query) == nil)
    }

    @Test func supportsOtherSitesAndCustomSearch() {
        #expect(SiteSearch.match("red")?.id == "reddit")
        #expect(SiteSearch.match("git")?.id == "github")
        #expect(SiteSearch.match("ama")?.id == "amazon")
        #expect(SiteSearch.match("wiki")?.id == "wikipedia")
        #expect(SiteSearch.match("goo")?.id == "google")
        let custom = SearchEngine.custom(name: "My library", template: "https://library.example/search?q=%s")
        #expect(SiteSearch.match("my lib", customEngine: custom) == custom)
        #expect(SiteSearch.match("library.example", customEngine: custom) == custom)
        let invalid = SearchEngine.custom(name: "Broken", template: "javascript:alert('%s')")
        #expect(SiteSearch.match("broken", customEngine: invalid) == nil)
    }

    @Test func encodesQueriesWithoutAddingParametersOrFragments() throws {
        let site = try #require(SiteSearch.match("you"))
        let query = "café & C++ #music? 你好 / 100%"
        let url = try #require(site.searchURL(for: query))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.host == "www.youtube.com")
        #expect(components.path == "/results")
        #expect(components.queryItems == [URLQueryItem(name: "search_query", value: query)])
        #expect(components.fragment == nil)
    }

    @Test func tabActivatesSiteAndEmptySubmitKeepsPaletteOpen() {
        let coordinator = AppCoordinator()
        var dismissed = false
        let model = CommandPaletteModel(browser: coordinator.browser, coordinator: coordinator) { dismissed = true }
        model.prepare()
        model.interaction.query = "You"
        #expect(model.suggestedSite?.name == "YouTube")
        #expect(model.activateSiteSearch())
        #expect(model.searchSite?.id == "youtube")
        #expect(model.placeholder == String(localized: "Search \("YouTube")"))
        #expect(model.interaction.query.isEmpty)
        #expect(model.suggestedSite == nil)
        #expect(model.sections.isEmpty)
        #expect(!model.activateSiteSearch())
        model.submit()
        model.submitInCurrentTab()
        #expect(!dismissed)
        model.interaction.query = "   "
        model.submit()
        #expect(!dismissed)
    }

    @Test func siteModeReplacesAssistantAndWebSuggestions() throws {
        Omnibox.$agentOnlyForTesting.withValue(true) {
            let coordinator = AppCoordinator()
            let model = CommandPaletteModel(browser: coordinator.browser, coordinator: coordinator) {}
            model.interaction.query = "you"
            #expect(model.activateSiteSearch())
            for query in ["music", "https://example.com", "> settings", "@a tab", "?a question"] {
                model.interaction.query = query
                #expect(model.sections.flattened.count == 1)
                #expect(model.sections.flattened.first?.id == "site-search-youtube")
                #expect(model.sections.flattened.first?.title == query)
                #expect(model.contextPages.isEmpty)
                #expect(model.suggestions.phrases.isEmpty)
            }
        }
    }

    @Test func removingSitePreservesQueryAndRestoresNormalResults() {
        let coordinator = AppCoordinator()
        let model = CommandPaletteModel(browser: coordinator.browser, coordinator: coordinator) {}
        model.interaction.query = "youtube"
        #expect(model.activateSiteSearch())
        model.interaction.query = "music"
        #expect(model.removeSearchSite())
        #expect(model.searchSite == nil)
        #expect(model.interaction.query == "music")
        #expect(!model.sections.flattened.contains { $0.id == "site-search-youtube" })
        #expect(!model.removeSearchSite())
    }

    @Test func mentionsDoNotActivateSiteSearch() {
        let coordinator = AppCoordinator()
        let tab = coordinator.browser.newTab()
        let model = CommandPaletteModel(browser: coordinator.browser, coordinator: coordinator) {}
        model.mention(tab)
        model.interaction.query = "you"
        #expect(model.suggestedSite == nil)
        #expect(!model.activateSiteSearch())
    }

    @Test(.boundedWebViews) func enterSearchesSiteInNewTab() {
        let coordinator = AppCoordinator()
        let previous = coordinator.browser.newTab()
        let count = coordinator.browser.tabs.count
        var dismissed = false
        let model = CommandPaletteModel(browser: coordinator.browser, coordinator: coordinator) { dismissed = true }
        model.interaction.query = "you"
        #expect(model.activateSiteSearch())
        model.interaction.query = "ambient music"
        model.submit()
        #expect(dismissed)
        #expect(coordinator.browser.tabs.count == count + 1)
        #expect(coordinator.browser.activeTab !== previous)
        #expect(coordinator.browser.activeTab?.urlString == "https://www.youtube.com/results?search_query=ambient%20music")
    }

    @Test(.boundedWebViews) func optionEnterSearchesSiteInCurrentTab() {
        let coordinator = AppCoordinator()
        let previous = coordinator.browser.newTab()
        let count = coordinator.browser.tabs.count
        let model = CommandPaletteModel(browser: coordinator.browser, coordinator: coordinator) {}
        model.interaction.query = "git"
        #expect(model.activateSiteSearch())
        model.interaction.query = "swift"
        model.submitInCurrentTab()
        #expect(coordinator.browser.tabs.count == count)
        #expect(coordinator.browser.activeTab === previous)
        #expect(previous.urlString == "https://github.com/search?q=swift")
    }
}
