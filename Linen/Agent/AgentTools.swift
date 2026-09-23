// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation

nonisolated struct WebSearchTool: Tool {
    let name = "searchWeb"
    let description = AgentToolkit.Descriptions.searchWeb
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

nonisolated struct NavigateTool: Tool {
    let name = "navigate"
    let description = AgentToolkit.Descriptions.navigate
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

nonisolated struct NewTabTool: Tool {
    let name = "newTab"
    let description = AgentToolkit.Descriptions.newTab
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

nonisolated struct AskUserTool: Tool {
    static let toolName = "askUser"
    let name = AskUserTool.toolName
    let description = AgentToolkit.Descriptions.askUser
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

nonisolated struct ListTabsTool: Tool {
    let name = "listTabs"
    let description = AgentToolkit.Descriptions.listTabs
    let toolkit: AgentToolkit

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await toolkit.listTabs()
    }
}

nonisolated struct SwitchTabTool: Tool {
    let name = "switchTab"
    let description = AgentToolkit.Descriptions.switchTab
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

nonisolated struct CloseTabTool: Tool {
    let name = "closeTab"
    let description = AgentToolkit.Descriptions.closeTab
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

nonisolated struct ReadPageTool: Tool {
    let name = "readPage"
    let description = AgentToolkit.Descriptions.readPage
    let toolkit: AgentToolkit

    @Generable
    struct Arguments {
        @Guide(description: "What you are looking for; the text returned is the part of the page about this. Empty for the top of the page.")
        var lookingFor: String
        @Guide(
            description:
                "Page ID, title, site, or split position. Empty for the active tab."
        )
        var page: String
        @Guide(description: "Continuation offset for page text; omit for the first excerpt.")
        var textOffset: Int?
        @Guide(description: "Use the suggested next controlOffset, not a [ref] number. Omit or use 0 when changing lookingFor, scope, or viewportOnly.")
        var controlOffset: Int?
        @Guide(description: "Optional CSS selector restricting the control list.")
        var scope: String?
        @Guide(description: "Only controls in the viewport when true.")
        var viewportOnly: Bool?

    }

    func call(arguments: Arguments) async throws -> String {
        await toolkit.readPage(
            lookingFor: arguments.lookingFor, page: arguments.page, textOffset: arguments.textOffset ?? 0, controlOffset: arguments.controlOffset ?? 0,
            scope: arguments.scope ?? "", viewportOnly: arguments.viewportOnly ?? false)
    }
}

nonisolated struct ClickOnPageTool: Tool {
    let name = "clickOnPage"
    let description = AgentToolkit.Descriptions.clickOnPage
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

nonisolated struct TypeOnPageTool: Tool {
    let name = "typeOnPage"
    let description = AgentToolkit.Descriptions.typeOnPage
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

nonisolated struct FillFieldsTool: Tool {
    let name = "fillFields"
    let description = """
        Fill up to eight independent fields or dropdowns without submitting. Use the latest observation. \
        Stops if the page changes; check the completed count before continuing.
        """
    let toolkit: AgentToolkit

    @Generable
    struct Field {
        @Guide(description: "The field ref from the latest page observation")
        var ref: Int
        @Guide(description: "Text to enter, or the dropdown option to select")
        var value: String
        @Guide(description: "True for a dropdown, false for a text field")
        var select: Bool
    }

    @Generable
    struct Arguments {
        @Guide(description: "Page ID or title. Omit for the active tab.")
        var page: String?
        @Guide(description: "Exact observationID from the latest read or action result.")
        var observationID: String

        @Guide(description: "One to eight independent fields, in order; never login or payment fields")
        var fields: [Field]
    }

    func call(arguments: Arguments) async throws -> String {
        guard !arguments.observationID.isEmpty else {
            return await toolkit.rejectTool(name: name, reason: "Read the page first and provide its observationID.")
        }
        return await toolkit.withPageContext(page: arguments.page, observationID: arguments.observationID) {
            await toolkit.fillFields(arguments.fields.map { .init(ref: $0.ref, value: $0.value, select: $0.select) })
        }
    }
}

nonisolated struct SelectOptionTool: Tool {
    let name = "selectOption"
    let description = AgentToolkit.Descriptions.selectOption
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

nonisolated struct ScrollPageTool: Tool {
    let name = "scrollPage"
    let description = AgentToolkit.Descriptions.scrollPage
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

nonisolated struct GoBackTool: Tool {
    let name = "goBack"
    let description = AgentToolkit.Descriptions.goBack
    let toolkit: AgentToolkit

    @Generable
    struct Arguments {
        var page: String?
    }

    func call(arguments: Arguments) async throws -> String {
        await toolkit.withPageContext(page: arguments.page, observationID: nil) { await toolkit.goBack() }
    }
}

nonisolated struct PlayVideoTool: Tool {
    let name = "playVideo"
    let description = AgentToolkit.Descriptions.playVideo
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

nonisolated struct CloseVideoTool: Tool {
    let name = "closeVideo"
    let description = AgentToolkit.Descriptions.closeVideo
    let toolkit: AgentToolkit

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await toolkit.closeVideo()
    }
}

nonisolated struct ControlMediaTool: Tool {
    let name = "controlMedia"
    let description = AgentToolkit.Descriptions.controlMedia
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

nonisolated enum AgentToolTier: Hashable, Sendable {
    case core
    case full
}

@MainActor
func makeAgentTools(toolkit: AgentToolkit, enabledIDs: Set<String>) -> [any Tool] {
    makeAgentTools(toolkit: toolkit, tier: .full).filter {
        $0.name == AskUserTool.toolName || AgentToolCatalog.outcomeToolIDs.contains($0.name) || enabledIDs.contains($0.name)
    }
}

@MainActor
func makeAgentTools(toolkit: AgentToolkit, tier: AgentToolTier = .full) -> [any Tool] {
    let core: [any Tool] = [
        AskUserTool(toolkit: toolkit),
        RecordTaskOutcomeTool(toolkit: toolkit),
        VerifyTaskOutcomeTool(toolkit: toolkit),
        BlockTaskOutcomeTool(toolkit: toolkit),
        WebSearchTool(toolkit: toolkit),
        NavigateTool(toolkit: toolkit),
        ReadPageTool(toolkit: toolkit),
        ClickOnPageTool(toolkit: toolkit),
        TypeOnPageTool(toolkit: toolkit),
        ScrollPageTool(toolkit: toolkit),
        GoBackTool(toolkit: toolkit),
    ]
    switch tier {
    case .core:
        return core
    case .full:
        return core + [
            NewTabTool(toolkit: toolkit),
            ListTabsTool(toolkit: toolkit),
            SwitchTabTool(toolkit: toolkit),
            CloseTabTool(toolkit: toolkit),
            SelectOptionTool(toolkit: toolkit),
            FillFieldsTool(toolkit: toolkit),
            InspectControlTool(toolkit: toolkit),
            SetCheckedTool(toolkit: toolkit),
            WaitForPageTool(toolkit: toolkit),
            ScreenshotPageTool(toolkit: toolkit),
            MovePointerTool(toolkit: toolkit),
            ClickAtPointTool(toolkit: toolkit),
            DoubleClickAtPointTool(toolkit: toolkit),
            DragOnPageTool(toolkit: toolkit),
            ListFramesTool(toolkit: toolkit),
            ReadFrameTool(toolkit: toolkit),
            ActInFrameTool(toolkit: toolkit),
            ChooseFilesOnPageTool(toolkit: toolkit),
            InspectDownloadsTool(toolkit: toolkit),
            TypeAtPointerTool(toolkit: toolkit),
            HoverOnPageTool(toolkit: toolkit),
            PressKeyTool(toolkit: toolkit),
            PlayVideoTool(toolkit: toolkit),
            CloseVideoTool(toolkit: toolkit),
            ControlMediaTool(toolkit: toolkit),
        ]
    }
}

nonisolated func estimatedToolSchemaTokens(_ tools: [any Tool]) -> Int {
    tools.reduce(0) { count, tool in
        let bytes = (try? JSONEncoder().encode(tool.parameters).count) ?? 600
        return count + (bytes + tool.name.utf8.count + tool.description.utf8.count + 3) / 4 + 16
    }
}
