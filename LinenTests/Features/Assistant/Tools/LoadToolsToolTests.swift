// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import Testing

@testable import Linen

@MainActor
struct LoadToolsToolTests {
    private func agent(
        enabled: Set<String>? = nil,
        small: Bool = true,
        schemaTokens: Int = 9_000,
        toolOverrides: [any Tool]? = nil,
        openAI: OpenAIResponsesClient? = nil
    ) -> AnyLanguageModelAgent {
        let log = ConversationLog(database: .temporary())
        return AnyLanguageModelAgent(
            name: "fixture", modelID: "fixture", toolOverrides: toolOverrides, openAI: openAI,
            model: HarnessScript([]), options: GenerationOptions(),
            budget: ContextBudget(windowTokens: small ? 4_096 : 128_000, responseTokens: 2_000, inputTokens: 100_000, toolSchemaTokens: schemaTokens,
                                  toolOutput: .standard,
                                  retainedExchanges: 12, retainedToolRounds: 3),
            acceptsImages: false,
            enabledToolIDs: enabled,
            toolkit: AgentToolkit(browser: BrowserModel(database: .temporary()), media: MediaCenter(), log: log),
            log: log
        )
    }

    static func calling(_ calls: [(String, String)]) throws -> Transcript {
        try Transcript(entries: calls.map { name, json in
            .toolCalls(.init([.init(id: UUID().uuidString, toolName: name, arguments: try GeneratedContent(json: json))]))
        })
    }

    static func reading(_ observation: String, tool: String = "readPage") -> Transcript {
        Transcript(entries: [.toolOutput(.init(id: UUID().uuidString, toolName: tool, segments: [.text(.init(content: observation))]))])
    }

    static func loading(_ tools: [String]) throws -> Transcript {
        let list = tools.map { "\"\($0)\"" }.joined(separator: ",")
        return try calling([(LoadToolsTool.toolName, "{\"tools\":[\(list)]}")])
    }

    private func names(_ agent: AnyLanguageModelAgent, _ transcript: Transcript = Transcript(entries: [])) -> [String] {
        agent.tools(for: transcript).map(\.name)
    }

    @Test func everyCatalogToolBelongsToExactlyOneGroup() {
        let grouped = AgentToolCatalog.groups.flatMap(\.toolIDs)
        let catalog = Set(AgentToolCatalog.all.map(\.id))

        #expect(grouped.count == Set(grouped).count)
        #expect(Set(grouped) == catalog)
    }

    @Test func everyPrerequisiteIsACatalogTool() {
        let catalog = Set(AgentToolCatalog.all.map(\.id))

        #expect(Set(AgentToolCatalog.prerequisites.keys).isSubset(of: catalog))
        #expect(Set(AgentToolCatalog.prerequisites.values).isSubset(of: catalog))
    }

    @Test func onlySmallWindowsDeferByDefault() {
        #expect(agent(small: true).defersTools)
        #expect(!agent(small: false).defersTools)
        #expect(names(agent(small: false)).contains("readPage"))
    }

    @Test func aSmallWindowOffersEveryToolItCanUse() throws {
        let loader = try #require(agent().tools(for: Transcript(entries: [])).compactMap { $0 as? LoadToolsTool }.first)
        let offered = Set(loader.toolNames)

        #expect(offered.contains("selectOption"))
        #expect(offered.contains("switchTab"))
        #expect(offered.contains("scrollPage"))
        #expect(offered.isDisjoint(with: AgentToolCatalog.visualToolIDs))
    }

    @Test func aFirstRequestCarriesOnlyTheLoaderAndTheAlwaysOnTools() {
        let first = names(agent())

        #expect(first.contains(LoadToolsTool.toolName))
        #expect(first.contains(AskUserTool.toolName))
        #expect(first.contains("readPage"))
        #expect(first.contains("goBack"))
        #expect(!first.contains("navigate"))
        #expect(first.allSatisfy { !AgentToolDeferral.isDeferrable($0) })
    }

    @Test func anEarlierProductPageIsFoundForAComparison() {
        let product = "Clicked “Birch desk lamp”. PAGE TEXT:\nHome · Lamps\nBirch desk lamp\nPrice $99\n\nCONTROLS:\n[1] link"
        let listing = "PAGE TEXT:\nHome · Lamps\nBirch desk lamp\nAster desk lamp\n\nCONTROLS:"
        let transcript = Transcript(entries: [product, listing].map { .toolOutput(.init(id: UUID().uuidString, toolName: "readPage", segments: [.text(.init(content: $0))])) })

        #expect(AnyLanguageModelAgent.earlierFinding(about: "Birch", not: "Aster", in: transcript)?.contains("Price $99") == true)
        #expect(AnyLanguageModelAgent.earlierFinding(about: "Cedar", in: transcript) == nil)
    }

    @Test func onlySmallWindowsStopReadingAfterARepeatedRead() {
        #expect(agent(small: true).withheldTools(afterRepeatedRead: true) == ["readPage", "readArticle"])
        #expect(agent(small: true).withheldTools(afterRepeatedRead: false).isEmpty)
        #expect(agent(small: false).withheldTools(afterRepeatedRead: true).isEmpty)
    }

    @Test func withheldToolsAreLeftOutOfTheTurn() {
        let subject = agent()
        subject.toolkit.turn.withheldTools = ["readPage"]

        #expect(!names(subject).contains("readPage"))
        #expect(names(subject).contains("goBack"))
    }

    @Test func theInitialSetFitsTheOnDeviceBudget() {
        let subject = agent()
        let initial = subject.toolSchemaTokens(for: Transcript(entries: []))

        #expect(initial < 900, "initial \(initial)")
    }

    @Test func loadingAToolBringsItsPrerequisiteFirst() throws {
        let loaded = names(agent(), try Self.loading(["actInFrame"]))

        #expect(Array(loaded.suffix(3)) == ["listFrames", "readFrame", "actInFrame"])
    }

    @Test func theLoaderReportsWhatItLoaded() async throws {
        let loader = LoadToolsTool(tools: makeAgentTools(toolkit: agent().toolkit).filter { AgentToolDeferral.isDeferrable($0.name) })

        let loaded = try await loader.call(arguments: GeneratedContent(json: #"{"tools":["clickOnPage"]}"#))
        let refused = try await loader.call(arguments: GeneratedContent(json: #"{"tools":["everything"]}"#))

        #expect(loaded == "Loaded. You can now call clickOnPage.")
        #expect(refused.hasPrefix("Name at least one tool"))
    }

    @Test func loadedToolsStayUnderTheCapByDroppingTheOldest() throws {
        let subject = agent(schemaTokens: 0)
        let always = estimatedToolSchemaTokens(subject.tools(for: Transcript(entries: [])))
        let byName = Dictionary(makeAgentTools(toolkit: subject.toolkit).map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let cap = always + estimatedToolSchemaTokens([byName["scrollPage"], byName["selectOption"]].compactMap { $0 }) + 1
        let capped = agent(schemaTokens: cap)
        let transcript = Transcript(entries: Array(try Self.loading(["switchTab"])) + Array(try Self.loading(["scrollPage"]))
            + Array(try Self.loading(["selectOption"])))
        let loaded = names(capped, transcript)

        #expect(loaded.contains("selectOption"))
        #expect(loaded.contains("scrollPage"))
        #expect(!loaded.contains("switchTab"))
        #expect(capped.toolSchemaTokens(for: transcript) <= cap)
    }

    @Test func usingAToolKeepsItLoaded() throws {
        let subject = agent(schemaTokens: 0)
        let always = estimatedToolSchemaTokens(subject.tools(for: Transcript(entries: [])))
        let capped = agent(schemaTokens: always + 250)
        let transcript = Transcript(entries: Array(try Self.loading(["switchTab"])) + Array(try Self.loading(["scrollPage"]))
            + Array(try Self.calling([("switchTab", "{\"reference\":\"Home\"}")])) + Array(try Self.loading(["goBack"])))
        let loaded = names(capped, transcript)

        #expect(loaded.contains("switchTab"))
        #expect(loaded.contains("goBack"))
        #expect(!loaded.contains("scrollPage"))
    }

    @Test func restoredInstructionsListTheLoadedTools() throws {
        let subject = agent()
        let transcript = Transcript(entries: Array(subject.makeSession().transcript) + Array(try Self.loading(["switchTab"])))
        let definitions = subject.makeSession(transcript: transcript).transcript.flatMap { entry -> [String] in
            guard case .instructions(let value) = entry else { return [] }
            return value.toolDefinitions.map(\.name)
        }

        #expect(definitions.contains("switchTab"))
        #expect(definitions.contains(LoadToolsTool.toolName))
        #expect(!definitions.contains("clickOnPage"))
    }

    @Test func loadedToolsSurviveDroppedToolRounds() throws {
        let subject = agent()
        let loaded = subject.makeSession(transcript: Transcript(entries: Array(subject.makeSession().transcript) + Array(try Self.loading(["switchTab"]))))
        let trimmed = Transcript(entries: Array(loaded.transcript).filter { if case .instructions = $0 { return true }; return false })

        #expect(names(subject, trimmed).contains("switchTab"))
    }

    @Test func readingAPageLoadsTheToolsForItsControls() {
        let observation = """
            PAGE TEXT:
            Woven throw

            CONTROLS:
            [5] select "Size" = "Small" (options: Small | Medium | Large)
            [6] checkbox "Gift wrap" (unchecked)
            [1] link "Home" → http://127.0.0.1/
            """
        let loaded = names(agent(), Self.reading(observation))

        #expect(loaded.contains("selectOption"))
        #expect(loaded.contains("setChecked"))
        #expect(loaded.contains("clickOnPage"))
        #expect(!loaded.contains("typeOnPage"))
    }

    @Test func eachControlKindNamesItsTools() {
        let observation = """
            CONTROLS:
            [1] field "Name" = (empty)
            [2] field "Photo" (file)
            [3] radio "Express" (unchecked)
            [4] scrollarea "List"
            """

        #expect(AgentToolCatalog.tools(forControlsIn: observation) == ["typeOnPage", "fillFields", "chooseFilesOnPage", "setChecked", "scrollPage"])
        #expect(AgentToolCatalog.tools(forControlsIn: "PAGE TEXT:\n[1] button \"Buy\"").isEmpty)
    }

    @Test func theRequestLoadsToolsItNames() {
        let request = Transcript(entries: [.prompt(.init(segments: [.text(.init(content: "Close the tab with the special offers."))]))])
        let loaded = names(agent(), request)

        #expect(loaded.contains("closeTab"))
        #expect(loaded.contains("listTabs"))
        #expect(!loaded.contains("pressKey"))
    }

    @Test func openingASiteOrSearchingLoadsNavigate() {
        let request = Transcript(entries: [.prompt(.init(segments: [.text(.init(content: "Open http://127.0.0.1:8080/shipping and tell me the return window."))]))])
        let search = Transcript(entries: [.toolOutput(.init(id: "s", toolName: "searchWeb", segments: [.text(.init(content: "1. Aster warranty"))]))])

        #expect(names(agent(), request).contains("navigate"))
        #expect(names(agent(), search).contains("navigate"))
    }

    @Test func theReadStreakNudgeNamesTheToolsThatCanAct() throws {
        let subject = agent()
        let nudge = subject.readStreakPrompt(for: Self.reading("CONTROLS:\n[5] select \"Size\" (options: Small | Large)"))

        #expect(nudge.hasPrefix(AnyLanguageModelAgent.readStreakPrompt))
        #expect(nudge.contains("selectOption"))
        #expect(!nudge.contains("readPage"))
        #expect(AnyLanguageModelAgent.isScaffolding(nudge))
        #expect(agent(small: false).readStreakPrompt(for: Self.reading("CONTROLS:\n[5] select \"Size\" (options: Small | Large)")) == nudge)
        #expect(agent(small: false).readStreakPrompt(for: Transcript(entries: [])) == AnyLanguageModelAgent.readStreakPrompt)
    }

    @Test func anAnswerOnlySessionOffersNoTools() throws {
        let subject = agent()
        let session = subject.makeSession(transcript: Transcript(entries: Array(subject.makeSession().transcript) + Array(try Self.loading(["switchTab"]))),
                                          withoutTools: true)
        let definitions = session.transcript.flatMap { entry -> [String] in
            guard case .instructions(let value) = entry else { return [] }
            return value.toolDefinitions.map(\.name)
        }

        #expect(definitions.isEmpty)
    }

    @Test func theStepPromptIsScaffolding() {
        #expect(AnyLanguageModelAgent.isScaffolding(AnyLanguageModelAgent.stepPrompt))
    }

    @Test func scaffoldingPromptsLoadNothing() {
        let subject = agent()
        let nudge = Transcript(entries: [.prompt(.init(segments: [.text(.init(content: AnyLanguageModelAgent.readStreakPrompt))]))])

        #expect(names(subject, nudge) == names(subject))
    }

    @Test func aToolAnOutputNamesIsLoaded() {
        let loaded = names(agent(), Self.reading("CONTROLS:\n[5] select \"Delivery\" (options: Standard | Express) (4 options; inspectControl for more)"))

        #expect(loaded.contains("inspectControl"))
        #expect(loaded.contains("selectOption"))
    }

    @Test func aSmallWindowReadsWithoutViewportOrScopeFilters() throws {
        let reader = try #require(makeAgentTools(toolkit: agent().toolkit).first { $0.name == "readPage" })
        let schema = try #require(String(data: try JSONEncoder().encode(reader.parameters), encoding: .utf8))

        #expect(schema.contains("lookingFor"))
        #expect(!schema.contains("viewportOnly"))
        #expect(!schema.contains("scope"))
    }

    @Test func embeddedPageControlsLoadNothing() {
        let subject = agent()

        #expect(names(subject, Self.reading("CONTROLS:\n[1] button \"Pay\"", tool: "readFrame")) == names(subject))
    }

    @Test func unknownToolsLoadNothing() throws {
        let subject = agent()

        #expect(names(subject, try Self.loading(["everything"])) == names(subject))
    }

    @Test func theLoaderSchemaListsTheToolNames() throws {
        let loader = LoadToolsTool(tools: makeAgentTools(toolkit: agent().toolkit).filter { AgentToolDeferral.isDeferrable($0.name) })
        let schema = try #require(String(data: try JSONEncoder().encode(loader.parameters), encoding: .utf8))

        #expect(schema.contains("selectOption"))
        #expect(!schema.contains(AskUserTool.toolName))
    }

    @Test func onlyADeferringAgentIsToldThatToolsStartUnloaded() {
        #expect(agent(small: true).instructionsText.contains(AgentInstructions.loaderGuidance))
        #expect(!agent(small: false).instructionsText.contains(AgentInstructions.loaderGuidance))
    }

    @Test func theModeSwitchOverridesTheWindow() {
        let large = agent(small: false)
        let small = agent(small: true)

        #expect(AgentToolDeferral.$mode.withValue(.always) { large.defersTools })
        #expect(!AgentToolDeferral.$mode.withValue(.never) { small.defersTools })
    }

    @Test func overridesAndHostedToolSearchKeepEveryTool() throws {
        let overrides = makeAgentTools(toolkit: agent().toolkit)
        let overridden = names(agent(toolOverrides: overrides))
        var settings = OpenAIResponseSettings()
        settings.useToolSearch = true
        let hosted = names(agent(openAI: OpenAIResponsesClient(
            endpoint: try #require(URL(string: "https://api.openai.com/v1")), apiKey: "test", model: "gpt-6-luna", settings: settings
        )))

        #expect(!overridden.contains(LoadToolsTool.toolName))
        #expect(overridden.contains("readPage"))
        #expect(!hosted.contains(LoadToolsTool.toolName))
        #expect(hosted.contains("readPage"))
    }
}
