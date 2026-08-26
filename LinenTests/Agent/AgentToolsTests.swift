// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import Testing

@testable import Linen

@MainActor
struct AgentToolsTests {
    private func tools() -> [any Tool] {
        makeAgentTools(toolkit: AgentToolkit(
            browser: BrowserModel(database: .temporary()),
            media: MediaCenter(),
            log: ConversationLog(database: .temporary())
        ))
    }

    @Test func everyToolHasItsOwnName() {
        let names = tools().map(\.name)
        #expect(names.count == Set(names).count)
    }

    @Test func noToolIsHandedOverNameless() {
        #expect(!tools().contains { $0.name.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    @Test func noToolIsHandedOverWithoutADescription() {
        for tool in tools() {
            #expect(!tool.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(tool.name)")
        }
    }

    @Test func everyToolCarriesItsOwnDescription() {
        let descriptions = tools().map(\.description)
        #expect(descriptions.count == Set(descriptions).count)
    }

    @Test func namesAreCallableIdentifiers() {
        let allowed = CharacterSet.alphanumerics
        for tool in tools() {
            #expect(tool.name.unicodeScalars.allSatisfy(allowed.contains), "\(tool.name)")
        }
    }

    @Test func theTableIsExactlyTheseSixteenTools() {
        #expect(Set(tools().map(\.name)) == [
            "askUser",
            "searchWeb",
            "navigate",
            "newTab",
            "listTabs",
            "switchTab",
            "closeTab",
            "readPage",
            "clickOnPage",
            "typeOnPage",
            "selectOption",
            "scrollPage",
            "goBack",
            "playVideo",
            "closeVideo",
            "controlMedia",
        ])
    }

    @Test func theTypingToolSaysWhatItWillRefuse() {
        let typing = tools().first { $0.name == "typeOnPage" }
        #expect(typing?.description.contains("refuses") == true)
        #expect(typing?.description.localizedCaseInsensitiveContains("password") == true)
    }

    @Test func theClickingToolSaysWhenItWillAsk() {
        let clicking = tools().first { $0.name == "clickOnPage" }
        #expect(clicking?.description.localizedCaseInsensitiveContains("asks before") == true)
    }
}
