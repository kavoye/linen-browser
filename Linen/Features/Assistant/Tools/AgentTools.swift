// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation

nonisolated struct WebSearchTool: AgentTool {
    static let toolName = "searchWeb"
    static let toolDescription = AgentToolkit.Descriptions.searchWeb
    let toolkit: AgentToolkit

    @Generable
    struct Arguments {
        @Guide(description: "The search query")
        var query: String
        @Guide(description: "Up to three additional independent queries to search concurrently.")
        var additionalQueries: [String]?
        @Guide(description: "Optional domain restriction, such as example.com.")
        var domain: String?
    }

    func call(arguments: Arguments) async throws -> String {
        await toolkit.searchWeb(query: arguments.query, additionalQueries: arguments.additionalQueries ?? [], domain: arguments.domain ?? "")
    }
}

nonisolated struct NavigateTool: AgentTool {
    static let toolName = "navigate"
    static let toolDescription = AgentToolkit.Descriptions.navigate
    let toolkit: AgentToolkit

    @Generable
    struct Arguments {
        @Guide(description: "The full http(s) URL to open")
        var url: String
    }

    func call(arguments: Arguments) async throws -> String {
        await toolkit.navigate(to: arguments.url)
    }
}

nonisolated struct NewTabTool: AgentTool {
    static let toolName = "newTab"
    static let toolDescription = AgentToolkit.Descriptions.newTab
    let toolkit: AgentToolkit

    @Generable
    struct Arguments {
        @Guide(description: "URL to open in the new tab, or empty for a blank tab")
        var url: String
    }

    func call(arguments: Arguments) async throws -> String {
        await toolkit.newTab(url: arguments.url.isEmpty ? nil : arguments.url)
    }
}

nonisolated struct AskUserTool: AgentTool {
    static let toolName = "askUser"
    static let toolDescription = AgentToolkit.Descriptions.askUser
    let toolkit: AgentToolkit

    @Generable
    nonisolated struct Question {
        @Guide(description: "One short question, in the second person")
        var question: String
        @Guide(description: "Answers to offer, or empty when the answer is open")
        var options: [String]
    }

    @Generable
    struct Arguments {
        @Guide(description: "Everything you need to know, asked one question at a time")
        var questions: [Question]
    }

    func call(arguments: Arguments) async throws -> String {
        await toolkit.askUser(arguments.questions.map { ($0.question, $0.options) })
    }
}

nonisolated struct ListTabsTool: AgentTool {
    static let toolName = "listTabs"
    static let toolDescription = AgentToolkit.Descriptions.listTabs
    let toolkit: AgentToolkit

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await toolkit.listTabs()
    }
}

nonisolated struct SwitchTabTool: AgentTool {
    static let toolName = "switchTab"
    static let toolDescription = AgentToolkit.Descriptions.switchTab
    let toolkit: AgentToolkit

    @Generable
    struct Arguments {
        @Guide(description: "Part of the tab's title or site name")
        var reference: String
    }

    func call(arguments: Arguments) async throws -> String {
        await toolkit.switchTab(matching: arguments.reference)
    }
}

nonisolated struct CloseTabTool: AgentTool {
    static let toolName = "closeTab"
    static let toolDescription = AgentToolkit.Descriptions.closeTab
    let toolkit: AgentToolkit

    @Generable
    struct Arguments {
        @Guide(description: "Part of the tab's title, or empty for the active tab")
        var reference: String
    }

    func call(arguments: Arguments) async throws -> String {
        await toolkit.closeTab(matching: arguments.reference.isEmpty ? nil : arguments.reference)
    }
}

nonisolated struct ReadPageTool: AgentTool {
    static let toolName = "readPage"
    static let toolDescription = AgentToolkit.Descriptions.readPage
    let toolkit: AgentToolkit

    @Generable
    struct Arguments {
        @Guide(description: "What you are looking for; the text returned is the part of the page about this. Empty for the top of the page.")
        var lookingFor: String
        @Guide(description: "Page ID, title, site, or split position. Empty for the active tab.")
        var page: String
        @Guide(description: "Only the textOffset a previous read suggested; omit otherwise.")
        var textOffset: Int?
        @Guide(description: "Only the controlOffset a previous read suggested; omit otherwise.")
        var controlOffset: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        await toolkit.readPage(
            lookingFor: arguments.lookingFor, page: arguments.page, textOffset: arguments.textOffset ?? 0, controlOffset: arguments.controlOffset ?? 0)
    }
}

nonisolated struct ReadArticleTool: AgentTool {
    static let toolName = "readArticle"
    static let toolDescription = AgentToolkit.Descriptions.readArticle
    let toolkit: AgentToolkit

    @Generable
    struct Arguments {
        @Guide(description: "Page ID, title, site, or split position. Empty for the active tab.")
        var page: String
        @Guide(description: "Continuation offset for article text; omit for the start.")
        var textOffset: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        await toolkit.readArticle(page: arguments.page, textOffset: arguments.textOffset ?? 0)
    }
}

nonisolated struct ClickOnPageTool: AgentTool {
    static let toolName = "clickOnPage"
    static let toolDescription = AgentToolkit.Descriptions.clickOnPage
    let toolkit: AgentToolkit

    @Generable
    struct Arguments {
        @Guide(description: "Page ID or title. Omit for the active tab.")
        var page: String?
        @Guide(description: "Exact observationID from the latest read or action result.")
        var observationID: String

        @Guide(description: "The [N] ref of the element, from the last readPage. 0 to match by label instead.")
        var ref: Int
        @Guide(description: "The visible label to match instead, e.g. \"Add to Bag\". Empty when using ref.")
        var label: String
    }

    func call(arguments: Arguments) async throws -> String {
        guard !arguments.observationID.isEmpty else {
            return await toolkit.rejectTool(name: name, reason: "Read the page first and provide its observationID.")
        }
        return await toolkit.withPageContext(page: arguments.page, observationID: arguments.observationID) {
            await toolkit.clickOnPage(ref: arguments.ref, label: arguments.label)
        }
    }
}

nonisolated struct TypeOnPageTool: AgentTool {
    static let toolName = "typeOnPage"
    static let toolDescription = AgentToolkit.Descriptions.typeOnPage
    let toolkit: AgentToolkit

    @Generable
    struct Arguments {
        @Guide(description: "Page ID or title. Omit for the active tab.")
        var page: String?
        @Guide(description: "Exact observationID from the latest read or action result.")
        var observationID: String

        @Guide(description: "The text to type")
        var text: String
        @Guide(description: "The [N] ref of the field, from the last readPage. 0 to match by label instead.")
        var ref: Int
        @Guide(description: "The field's placeholder or label to match instead, e.g. \"Search\". Empty when using ref.")
        var field: String
        @Guide(description: "Whether to press Enter after typing")
        var submit: Bool
    }

    func call(arguments: Arguments) async throws -> String {
        guard !arguments.observationID.isEmpty else {
            return await toolkit.rejectTool(name: name, reason: "Read the page first and provide its observationID.")
        }
        return await toolkit.withPageContext(page: arguments.page, observationID: arguments.observationID) {
            await toolkit.typeOnPage(
                text: arguments.text,
                field: arguments.field,
                ref: arguments.ref,
                submit: arguments.submit
            )
        }
    }
}

nonisolated struct FillFieldsTool: AgentTool {
    static let toolName = "fillFields"
    static let toolDescription = AgentToolkit.Descriptions.fillFields
    let toolkit: AgentToolkit

    @Generable
    struct Field {
        @Guide(description: "The field ref from the latest page observation")
        var ref: Int
        @Guide(description: "Text, dropdown option, #RRGGBB color, numeric range value, or true/false for a checkbox or radio")
        var value: String
    }

    @Generable
    struct Arguments {
        @Guide(description: "Page ID or title. Omit for the active tab.")
        var page: String?
        @Guide(description: "Exact observationID from the latest read or action result.")
        var observationID: String

        @Guide(description: "One to 32 independent controls, in order; exclude sensitive, disabled, read-only, and file inputs")
        var fields: [Field]
    }

    func call(arguments: Arguments) async throws -> String {
        guard !arguments.observationID.isEmpty else {
            return await toolkit.rejectTool(name: name, reason: "Read the page first and provide its observationID.")
        }
        return await toolkit.withPageContext(page: arguments.page, observationID: arguments.observationID) {
            await toolkit.fillFields(arguments.fields.map { .init(ref: $0.ref, value: $0.value) })
        }
    }
}

nonisolated struct SelectOptionTool: AgentTool {
    static let toolName = "selectOption"
    static let toolDescription = AgentToolkit.Descriptions.selectOption
    let toolkit: AgentToolkit

    @Generable
    struct Arguments {
        @Guide(description: "Page ID or title. Omit for the active tab.")
        var page: String?
        @Guide(description: "Exact observationID from the latest read or action result.")
        var observationID: String

        @Guide(description: "The visible text of the option to choose")
        var option: String
        @Guide(description: "The [N] ref of the select, from the last readPage. 0 to match by label instead.")
        var ref: Int
        @Guide(description: "The select's label to match instead. Empty when using ref.")
        var field: String
    }

    func call(arguments: Arguments) async throws -> String {
        guard !arguments.observationID.isEmpty else {
            return await toolkit.rejectTool(name: name, reason: "Read the page first and provide its observationID.")
        }
        return await toolkit.withPageContext(page: arguments.page, observationID: arguments.observationID) {
            await toolkit.selectOption(arguments.option, ref: arguments.ref, field: arguments.field)
        }
    }
}

nonisolated struct ScrollPageTool: AgentTool {
    static let toolName = "scrollPage"
    static let toolDescription = AgentToolkit.Descriptions.scrollPage
    let toolkit: AgentToolkit

    @Generable
    struct Arguments {
        @Guide(description: "up, down, left, or right")
        var direction: String
        var page: String?
        var observationID: String?
        @Guide(description: "Optional control inside a scrollable container; omit for the document.") var ref: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        await toolkit.withPageContext(page: arguments.page, observationID: arguments.observationID) {
            if let ref = arguments.ref, ref > 0 {
                guard arguments.observationID != nil else { return "Provide observationID for a container ref." }
                return await toolkit.pageOperation(name: name) { view in
                    await PageDriver.scroll(direction: arguments.direction, ref: ref, in: view)
                }
            }
            return await toolkit.scrollPage(direction: arguments.direction)
        }
    }
}

nonisolated struct GoBackTool: AgentTool {
    static let toolName = "goBack"
    static let toolDescription = AgentToolkit.Descriptions.goBack
    let toolkit: AgentToolkit

    @Generable
    struct Arguments {
        var page: String?
    }

    func call(arguments: Arguments) async throws -> String {
        await toolkit.withPageContext(page: arguments.page, observationID: nil) { await toolkit.goBack() }
    }
}

nonisolated struct PlayVideoTool: AgentTool {
    static let toolName = "playVideo"
    static let toolDescription = AgentToolkit.Descriptions.playVideo
    let toolkit: AgentToolkit

    @Generable
    struct Arguments {
        @Guide(description: "Short video search topic")
        var topic: String
    }

    func call(arguments: Arguments) async throws -> String {
        await toolkit.playVideo(topic: arguments.topic)
    }
}

nonisolated struct CloseVideoTool: AgentTool {
    static let toolName = "closeVideo"
    static let toolDescription = AgentToolkit.Descriptions.closeVideo
    let toolkit: AgentToolkit

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await toolkit.closeVideo()
    }
}

nonisolated struct ControlMediaTool: AgentTool {
    static let toolName = "controlMedia"
    static let toolDescription = AgentToolkit.Descriptions.controlMedia
    let toolkit: AgentToolkit

    @Generable
    struct Arguments {
        @Guide(description: "One of: \"pip\", \"exitPip\"")
        var action: String
    }

    func call(arguments: Arguments) async throws -> String {
        await toolkit.controlMedia(action: arguments.action)
    }
}

nonisolated struct WatchPageTool: AgentTool {
    static let toolName = "watchPage"
    static let toolDescription = AgentToolkit.Descriptions.watchPage
    let toolkit: AgentToolkit

    @Generable
    struct Arguments {
        @Guide(description: "Page ID or title. Omit for the active tab.")
        var page: String?
        @Guide(description: "What the person is waiting for, in their words, like \"price below $50\" or \"back in stock\". Empty for any change.")
        var condition: String
        @Guide(description: "Minutes between checks, from 5 to 1440. Use 60 unless the person asks.")
        var everyMinutes: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await toolkit.withPageContext(page: arguments.page, observationID: nil) {
            await toolkit.watchPage(condition: arguments.condition, everyMinutes: arguments.everyMinutes)
        }
    }
}

nonisolated struct ListWatchesTool: AgentTool {
    static let toolName = "listWatches"
    static let toolDescription = AgentToolkit.Descriptions.listWatches
    let toolkit: AgentToolkit

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await toolkit.listWatches()
    }
}

nonisolated struct StopWatchTool: AgentTool {
    static let toolName = "stopWatch"
    static let toolDescription = AgentToolkit.Descriptions.stopWatch
    let toolkit: AgentToolkit

    @Generable
    struct Arguments {
        @Guide(description: "Watch ID, or part of the page title, address or condition")
        var reference: String
    }

    func call(arguments: Arguments) async throws -> String {
        await toolkit.stopWatch(matching: arguments.reference)
    }
}

@MainActor
func makeAgentTools(toolkit: AgentToolkit, enabledIDs: Set<String>) -> [any Tool] {
    makeAgentTools(toolkit: toolkit).filter { $0.name == AskUserTool.toolName || enabledIDs.contains($0.name) }
}

nonisolated protocol AgentTool: Tool {
    static var toolName: String { get }
    static var toolDescription: String { get }
    static var argumentSchema: GenerationSchema { get }
    init(toolkit: AgentToolkit)
}

nonisolated extension AgentTool {
    var name: String {
        Self.toolName
    }

    var description: String {
        Self.toolDescription
    }
}

nonisolated extension AgentTool where Arguments: Generable {
    static var argumentSchema: GenerationSchema {
        Arguments.generationSchema
    }
}

nonisolated let agentToolTypes: [any AgentTool.Type] = [
    AskUserTool.self,
    WebSearchTool.self,
    NavigateTool.self,
    ReadPageTool.self,
    ReadArticleTool.self,
    ClickOnPageTool.self,
    TypeOnPageTool.self,
    ScrollPageTool.self,
    GoBackTool.self,
    NewTabTool.self,
    ListTabsTool.self,
    SwitchTabTool.self,
    CloseTabTool.self,
    SelectOptionTool.self,
    FillFieldsTool.self,
    InspectControlTool.self,
    SetCheckedTool.self,
    WaitForPageTool.self,
    ScreenshotPageTool.self,
    MovePointerTool.self,
    ClickAtPointTool.self,
    DoubleClickAtPointTool.self,
    DragOnPageTool.self,
    ListFramesTool.self,
    ReadFrameTool.self,
    ActInFrameTool.self,
    ChooseFilesOnPageTool.self,
    InspectDownloadsTool.self,
    TypeAtPointerTool.self,
    HoverOnPageTool.self,
    PressKeyTool.self,
    PlayVideoTool.self,
    CloseVideoTool.self,
    ControlMediaTool.self,
    WatchPageTool.self,
    ListWatchesTool.self,
    StopWatchTool.self,
]

@MainActor
func makeAgentTools(toolkit: AgentToolkit) -> [any Tool] {
    agentToolTypes.map { $0.init(toolkit: toolkit) }
}

nonisolated func estimatedToolSchemaTokens(_ tools: [any Tool]) -> Int {
    tools.reduce(0) { count, tool in
        let bytes = (try? JSONEncoder().encode(tool.parameters).count) ?? 600
        return count + (bytes + tool.name.utf8.count + tool.description.utf8.count + 3) / 4 + 16
    }
}
