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

    @Test func actionsRequireTheObservationTheyUseAndSchemasAreMeasured() throws {
        for tool in tools().filter({ ["clickOnPage", "typeOnPage", "fillFields", "selectOption", "setChecked", "pressKey", "hoverOnPage"].contains($0.name) }) {
            let data = try JSONEncoder().encode(tool.parameters)
            var schema = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            if let reference = schema["$ref"] as? String, let name = reference.split(separator: "/").last,
               let definitions = schema["$defs"] as? [String: [String: Any]] {
                schema = try #require(definitions[String(name)])
            }
            #expect((schema["required"] as? [String])?.contains("observationID") == true, "\(tool.name)")
        }
        let actual = tools() + [UpdateProgressTool()]
        let measured = estimatedToolSchemaTokens(actual)
        let budget = ContextBudget.resolve(windowTokens: 128_000, desiredResponseTokens: 4000, measuredSchemaTokens: measured)
        #expect(budget.toolSchemaTokens == measured)
        #expect(measured > actual.count * 75)
    }

    @Test func theTableIncludesFormBatching() {
        #expect(Set(tools().map(\.name)) == [
            "askUser",
            "recordTaskOutcome", "verifyTaskOutcome", "blockTaskOutcome",
            "doubleClickAtPoint", "dragOnPage", "listFrames", "readFrame", "actInFrame", "chooseFilesOnPage", "inspectDownloads",
            "searchWeb",
            "navigate",
            "newTab",
            "listTabs",
            "switchTab",
            "closeTab",
            "readPage",
            "clickOnPage",
            "typeOnPage",
            "fillFields",
            "inspectControl",
            "setChecked",
            "waitForPage",
            "screenshotPage",
            "movePointer",
            "clickAtPoint",
            "typeAtPointer",
            "hoverOnPage",
            "pressKey",
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
