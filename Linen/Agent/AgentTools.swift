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
    }

    func call(arguments: Arguments) async throws -> String {
        await toolkit.searchWeb(query: arguments.query)
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
        @Guide(description: "Which page on screen to read, by title, site name, or position (\"left\", \"right\", \"top\", \"bottom\", or \"first\" to \"fourth\"). Empty for the active one.")
        var page: String
    }

    func call(arguments: Arguments) async throws -> String {
        await toolkit.readPage(lookingFor: arguments.lookingFor, page: arguments.page)
    }
}

nonisolated struct ClickOnPageTool: Tool {
    let name = "clickOnPage"
    let description = AgentToolkit.Descriptions.clickOnPage
    let toolkit: AgentToolkit

    @Generable
    struct Arguments {
        @Guide(description: "The [N] ref of the element, from the last readPage. 0 to match by label instead.")
        var ref: Int
        @Guide(description: "The visible label to match instead, e.g. \"Add to Bag\". Empty when using ref.")
        var label: String
    }

    func call(arguments: Arguments) async throws -> String {
        await toolkit.clickOnPage(ref: arguments.ref, label: arguments.label)
    }
}

nonisolated struct TypeOnPageTool: Tool {
    let name = "typeOnPage"
    let description = AgentToolkit.Descriptions.typeOnPage
    let toolkit: AgentToolkit

    @Generable
    struct Arguments {
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
        await toolkit.typeOnPage(
            text: arguments.text,
            field: arguments.field,
            ref: arguments.ref,
            submit: arguments.submit
        )
    }
}

nonisolated struct SelectOptionTool: Tool {
    let name = "selectOption"
    let description = AgentToolkit.Descriptions.selectOption
    let toolkit: AgentToolkit

    @Generable
    struct Arguments {
        @Guide(description: "The visible text of the option to choose")
        var option: String
        @Guide(description: "The [N] ref of the select, from the last readPage. 0 to match by label instead.")
        var ref: Int
        @Guide(description: "The select's label to match instead. Empty when using ref.")
        var field: String
    }

    func call(arguments: Arguments) async throws -> String {
        await toolkit.selectOption(arguments.option, ref: arguments.ref, field: arguments.field)
    }
}

nonisolated struct ScrollPageTool: Tool {
    let name = "scrollPage"
    let description = AgentToolkit.Descriptions.scrollPage
    let toolkit: AgentToolkit

    @Generable
    struct Arguments {
        @Guide(description: "Either \"down\" or \"up\"")
        var direction: String
    }

    func call(arguments: Arguments) async throws -> String {
        await toolkit.scrollPage(direction: arguments.direction)
    }
}

nonisolated struct GoBackTool: Tool {
    let name = "goBack"
    let description = AgentToolkit.Descriptions.goBack
    let toolkit: AgentToolkit

    @Generable
    struct Arguments {
        @Guide(description: "Always \"back\"")
        var confirm: String
    }

    func call(arguments: Arguments) async throws -> String {
        await toolkit.goBack()
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
    struct Arguments {
        @Guide(description: "Always \"close\"")
        var confirm: String
    }

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
        @Guide(description: "One of: \"pip\", \"exitPip\", \"expand\", \"collapse\"")
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
    makeAgentTools(toolkit: toolkit, tier: .full).filter { enabledIDs.contains($0.name) }
}

@MainActor
func makeAgentTools(toolkit: AgentToolkit, tier: AgentToolTier = .full) -> [any Tool] {
    let core: [any Tool] = [
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
            SwitchTabTool(toolkit: toolkit),
            CloseTabTool(toolkit: toolkit),
            SelectOptionTool(toolkit: toolkit),
            PlayVideoTool(toolkit: toolkit),
            CloseVideoTool(toolkit: toolkit),
            ControlMediaTool(toolkit: toolkit),
        ]
    }
}
