// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

struct SettingsSearchTests {
    @Test func everySearchEntryHasAUniqueAnchor() {
        let ids = SettingsIndex.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func anEmptyQueryHasNoResults() {
        #expect(SettingsIndex.search("   ").isEmpty)
    }

    @Test func titleMatchesRankBeforeKeywordMatches() {
        let results = SettingsIndex.search("search")
        #expect(results.first?.id == "search.engine")
        #expect(results.contains { $0.id == "general.agentOnly" })
    }

    @Test func keywordsFindSettingsByCommonLanguage() {
        let results = SettingsIndex.search("hotkey")
        #expect(results.contains { $0.id == "voice.talk" })
        #expect(SettingsIndex.search("activation").contains { $0.id == "voice.talk" })
    }

    @Test func theVoiceRowsLiveOnTheAssistantPage() {
        let voice = SettingsIndex.all.filter { $0.id.hasPrefix("voice.") }
        #expect(voice.count == 2)
        #expect(voice.allSatisfy { $0.category == .provider })
    }

    @Test func theLinkSummaryRowLivesOnTheAssistantPage() {
        let entry = SettingsIndex.all.first { $0.id == "assistant.linkPeek" }
        #expect(entry?.category == .provider)
        #expect(SettingsIndex.search("summarize").contains { $0.id == "assistant.linkPeek" })
    }

    @Test func searchMatchesWordsInsideTitles() {
        #expect(SettingsIndex.search("links").contains { $0.id == "general.defaultBrowser" })
    }

    @Test func theOldRowNamesStillFindTheirRows() {
        #expect(SettingsIndex.search("provider").contains { $0.id == "provider.model" })
        #expect(SettingsIndex.search("default browser").contains { $0.id == "general.defaultBrowser" })
        #expect(SettingsIndex.search("ask instead of search").contains { $0.id == "general.agentOnly" })
    }

    @Test func theAssistantToggleIsFoundByTheWordAI() {
        #expect(SettingsIndex.search("ai").contains { $0.id == "general.agentOnly" })
        #expect(String(localized: SettingsIndex.all.first { $0.id == "general.agentOnly" }!.title)
            == "Always ask the assistant")
    }

    @Test func perSiteRulesAreFoundOnTheWebsiteList() {
        #expect(SettingsIndex.search("read only").contains { $0.id == "websites.list" })
        #expect(SettingsIndex.search("keep active").contains { $0.id == "websites.list" })
        #expect(SettingsIndex.search("always loaded").contains { $0.id == "websites.list" })
        #expect(!SettingsIndex.all.contains { $0.id == "websites.assistantAccess" })
        #expect(!SettingsIndex.all.contains { $0.id == "websites.alwaysActive" })
    }

    /// The toggle became the grey swatch in the profile editor, so searching
    /// for it lands on the profile list instead.
    @Test func theProfileColourToggleIsGoneButGreyStillFindsProfiles() {
        #expect(!SettingsIndex.all.contains { $0.id == "profiles.sidebarColor" })
        #expect(SettingsIndex.search("grey").contains { $0.id == "profiles.list" })
    }

    /// The time range moved inside the clear alert; it is not a row of its
    /// own, but searching for it still finds the clear section.
    @Test func timeRangeIsFoundInsideClearBrowsingData() {
        #expect(!SettingsIndex.all.contains { $0.searchableTitle == "Time range" })
        #expect(SettingsIndex.search("time range").contains { $0.id == "privacy.clear" })
    }

    @Test func providerAndAppearanceControlsHaveSearchResults() {
        #expect(SettingsIndex.search("API key").contains { $0.id == "provider.key" })
        #expect(SettingsIndex.search("endpoint").contains { $0.id == "provider.endpoint" })
        #expect(SettingsIndex.search("transparency").contains { $0.id == "appearance.transparency" })
        #expect(SettingsIndex.all.first { $0.id == "appearance.transparency" }?.targetAnchor
            == "appearance.windowStyle")
    }

    @Test func openAISettingsBehindProviderNavigationAreSearchable() {
        let expected: [(String, String)] = [
            ("reply length", "openai.replyLength"),
            ("speaking style", "openai.voice.speakingStyle"),
            ("reading speed", "openai.voice.readingSpeed"),
            ("MCP", "openai.connections"),
            ("keep replies", "openai.privacy"),
            ("run commands at OpenAI", "openai.developer.runCommands"),
            ("voice models", "openai.developer.voiceModels"),
            ("API JSON", "openai.developer.apiJSON"),
        ]
        for (query, id) in expected {
            #expect(SettingsIndex.search(query).contains { $0.id == id })
        }
    }

    @Test func newerAssistantAndExtensionControlsAreSearchable() {
        #expect(SettingsIndex.search("pause after").contains { $0.id == "assistant.pauseAfter" })
        #expect(SettingsIndex.search("embedded pages").contains { $0.id == "provider.tools" })
        #expect(SettingsIndex.search("choose files to upload").contains { $0.id == "provider.tools" })
        #expect(SettingsIndex.search("safari extensions").contains { $0.id == "extensions.installed" })
        #expect(SettingsIndex.search("save suggestions").contains { $0.id == "autofill.passwords" })
    }
}
