// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation

nonisolated struct HoverOnPageTool: Tool {
    let name = "hoverOnPage"
    let description = "Dispatch pointer and mouse hover handlers to a control. CSS-only hover is unavailable. Verify the returned page for revealed content."
    let toolkit: AgentToolkit
    @Generable struct Arguments {
        var page: String?
        var observationID: String
        var ref: Int
    }
    func call(arguments: Arguments) async throws -> String {
        await toolkit.withPageContext(page: arguments.page, observationID: arguments.observationID) {
            await toolkit.pageOperation(name: name) { view in await PageDriver.hover(ref: arguments.ref, in: view) }
        }
    }
}

nonisolated struct PressKeyTool: Tool {
    let name = "pressKey"
    let description =
        "Focus a control in a visible tab and send a key: Enter, Tab, Escape, Space, ArrowLeft, ArrowRight, ArrowDown, ArrowUp, Home, End, Backspace, or Delete. Use typeOnPage for text."
    let toolkit: AgentToolkit
    @Generable struct Arguments {
        var page: String?
        var observationID: String
        var ref: Int
        var key: String
    }
    func call(arguments: Arguments) async throws -> String {
        await toolkit.withPageContext(page: arguments.page, observationID: arguments.observationID) {
            await toolkit.pageOperation(name: name) { view in await PageDriver.pressKey(arguments.key, ref: arguments.ref, in: view) }
        }
    }
}

nonisolated struct InspectControlTool: Tool {
    let name = "inspectControl"
    let description = "Inspect a control's state, bounds, and dropdown options. Use offset to continue the option list."
    let toolkit: AgentToolkit
    @Generable struct Arguments {
        var page: String?
        var observationID: String
        var ref: Int
        var offset: Int?
    }
    func call(arguments: Arguments) async throws -> String {
        await toolkit.withPageContext(page: arguments.page, observationID: arguments.observationID) {
            await toolkit.pageOperation(name: name, readOnly: true) { view in
                await PageDriver.inspectControl(ref: arguments.ref, offset: arguments.offset ?? 0, in: view)
            }
        }
    }
}

nonisolated struct SetCheckedTool: Tool {
    let name = "setChecked"
    let description = "Set a checkbox, switch, or radio to the requested state. Avoid toggling a control already in that state."
    let toolkit: AgentToolkit
    @Generable struct Arguments {
        var page: String?
        var observationID: String
        var ref: Int
        var checked: Bool
    }
    func call(arguments: Arguments) async throws -> String {
        await toolkit.withPageContext(page: arguments.page, observationID: arguments.observationID) {
            await toolkit.pageOperation(name: name) { view in
                await PageDriver.setChecked(ref: arguments.ref, checked: arguments.checked, in: view, announced: true)
            }
        }
    }
}

nonisolated struct WaitForPageTool: Tool {
    let name = "waitForPage"
    let description = "Wait for text, textAbsent, a URL substring, or document ready. Returns one fresh observation. Use for an expected asynchronous change."
    let toolkit: AgentToolkit
    @Generable struct Arguments {
        var page: String?
        @Guide(description: "text, textAbsent, url, or ready") var condition: String
        var value: String
        @Guide(description: "Seconds, 1–15. Defaults to 5.") var timeout: Int?
    }
    func call(arguments: Arguments) async throws -> String {
        await toolkit.withPageContext(page: arguments.page, observationID: nil) {
            await toolkit.pageOperation(name: name, readOnly: true) { view in
                await PageDriver.waitForPage(condition: arguments.condition, value: arguments.value, timeout: arguments.timeout ?? 5, in: view)
            }
        }
    }
}

nonisolated struct ScreenshotPageTool: Tool {
    let name = "screenshotPage"
    let description =
        "Capture the current viewport when visual layout matters. Costs image tokens; prefer readPage for text and controls. Filled sensitive fields prevent capture."
    let toolkit: AgentToolkit
    @Generable struct Arguments {
        var page: String?
    }
    func call(arguments: Arguments) async throws -> String {
        await toolkit.withPageContext(page: arguments.page, observationID: nil) { await toolkit.screenshotPage() }
    }
}

nonisolated struct MovePointerTool: Tool {
    let name = "movePointer"
    let description = "Move the visible assistant pointer to pixel coordinates in the latest screenshot. Capture the page first. Use for visual hover when page controls are unavailable."
    let toolkit: AgentToolkit
    @Generable struct Arguments {
        var page: String?
        var x: Int
        var y: Int
    }
    func call(arguments: Arguments) async throws -> String {
        await toolkit.withPageContext(page: arguments.page, observationID: nil) {
            await toolkit.visualAction(name: name, action: ["type": "move", "x": .integer(Int64(arguments.x)), "y": .integer(Int64(arguments.y))])
        }
    }
}

nonisolated struct ClickAtPointTool: Tool {
    let name = "clickAtPoint"
    let description = "Click pixel coordinates in the latest screenshot with the visible assistant pointer. Capture the page first. Prefer clickOnPage when a numbered control is available."
    let toolkit: AgentToolkit
    @Generable struct Arguments {
        var page: String?
        var x: Int
        var y: Int
    }
    func call(arguments: Arguments) async throws -> String {
        await toolkit.withPageContext(page: arguments.page, observationID: nil) {
            await toolkit.visualAction(name: name, action: ["type": "click", "button": "left", "x": .integer(Int64(arguments.x)), "y": .integer(Int64(arguments.y))])
        }
    }
}

nonisolated struct TypeAtPointerTool: Tool {
    let name = "typeAtPointer"
    let description = "Type into the field focused by a visual click. Use the latest screenshot; filled sensitive fields are blocked. Prefer typeOnPage when a numbered field is available."
    let toolkit: AgentToolkit
    @Generable struct Arguments {
        var page: String?
        var text: String
    }
    func call(arguments: Arguments) async throws -> String {
        await toolkit.withPageContext(page: arguments.page, observationID: nil) {
            await toolkit.visualAction(name: name, action: ["type": "type", "text": .string(arguments.text)])
        }
    }
}
