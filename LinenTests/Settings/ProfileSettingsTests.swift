// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@MainActor
@Suite(.serialized)
struct ProfileSettingsTests {
    private func suite() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "ProfileSettingsTests.\(UUID().uuidString)"))
    }

    private func forget(_ suite: UserDefaults) {
        suite.removePersistentDomain(forName: suite.description)
    }

    @Test func theSessionAndAppHalvesAreDisjoint() {
        let session = Set(BrowserSettings.sessionKeys)
        for key in ["appearance.mode", "content.defaultZoom", "downloads.folder",
                    "advanced.userAgent", "advanced.webInspector", "appearance.reportIssueButton",
        ] {
            #expect(!session.contains(key))
        }
        for key in ["search.engine", "startup.newTab", "content.javaScript",
                    "privacy.clearOnQuit", "content.autoplay", "startPage.order",
        ] {
            #expect(session.contains(key))
        }
    }

    @Test func aSessionSettingFollowsTheProfileAndAnAppSettingDoesNot() throws {
        let app = try suite()
        let work = try suite()
        let personal = try suite()
        defer { [app, work, personal].forEach(forget) }

        let settings = BrowserSettings(defaults: app, sessionDefaults: work)
        settings.searchEngineID = "kagi"
        settings.appearance = .dark

        settings.useSessionDefaults(personal)
        #expect(settings.searchEngineID == SearchEngine.duckDuckGo.id)
        #expect(settings.appearance == .dark)

        settings.useSessionDefaults(work)
        #expect(settings.searchEngineID == "kagi")
    }

    @Test func switchingBackFindsWhatWasLeftBehind() throws {
        let app = try suite()
        let work = try suite()
        let personal = try suite()
        defer { [app, work, personal].forEach(forget) }

        let settings = BrowserSettings(defaults: app, sessionDefaults: work)
        settings.javaScriptEnabled = false
        settings.homepage = "example.com"

        settings.useSessionDefaults(personal)
        #expect(settings.javaScriptEnabled)
        #expect(settings.homepage.isEmpty)

        settings.useSessionDefaults(work)
        #expect(!settings.javaScriptEnabled)
        #expect(settings.homepage == "example.com")
    }

    @Test func theProviderAndModelAreWrittenWhereTheProfilePointsThem() throws {
        let work = try suite()
        defer {
            LLMSettings.defaults = .standard
            forget(work)
        }

        LLMSettings.defaults = work
        LLMSettings.providerID = "anthropic"
        LLMSettings.reasoningEffort = .high
        LLMSettings.setModel("claude-sonnet-5", for: ProviderCatalog.openAI)

        #expect(work.string(forKey: "llm.provider") == "anthropic")
        #expect(work.string(forKey: "llm.reasoningEffort") == "high")
        #expect(work.string(forKey: "llm.model.\(ProviderCatalog.openAI.id)") == "claude-sonnet-5")
        #expect(UserDefaults.standard.string(forKey: "llm.provider") != "anthropic")
    }

    @Test func eachProfileGetsItsOwnSuiteAndIconFolder() {
        let work = Profile(id: UUID(), name: "Work", symbol: "briefcase", color: .blue)
        let personal = Profile(id: UUID(), name: "Personal", symbol: "person", color: .green)

        #expect(ProfileSettingsStore.suiteName(for: work.id) != ProfileSettingsStore.suiteName(for: personal.id))
        #expect(FaviconLoader.cacheDirectory(for: work) != FaviconLoader.cacheDirectory(for: personal))
    }
}
