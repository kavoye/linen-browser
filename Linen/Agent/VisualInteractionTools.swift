// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel

nonisolated struct DoubleClickAtPointTool: Tool {
    let name = "doubleClickAtPoint"
    let description = "Double-click pixel coordinates in the latest screenshot. Capture the page first. Returns an updated screenshot."
    let toolkit: AgentToolkit
    @Generable struct Arguments {
        var page: String?
        var x: Int
        var y: Int
    }
    func call(arguments: Arguments) async throws -> String {
        await toolkit.withPageContext(page: arguments.page, observationID: nil) {
            await toolkit.visualAction(name: name, action: ["type": "double_click", "button": "left",
                "x": .integer(Int64(arguments.x)), "y": .integer(Int64(arguments.y)),
            ])
        }
    }
}

nonisolated struct DragOnPageTool: Tool {
    let name = "dragOnPage"
    let description = """
        Drag along 2–50 pixel points in the latest screenshot using DOM pointer or HTML drag events. Include the start and destination. \
        Capture the page first. Some sites require trusted native drags and will ignore these events. Inspect the updated screenshot and verify the result.
        """
    let toolkit: AgentToolkit
    @Generable struct Point {
        var x: Int
        var y: Int
    }
    @Generable struct Arguments {
        var page: String?
        var path: [Point]
    }
    func call(arguments: Arguments) async throws -> String {
        guard (2...50).contains(arguments.path.count) else {
            return await toolkit.rejectTool(name: name, reason: "Provide a drag path with 2–50 points.")
        }
        let path: [OpenAIJSON] = arguments.path.map { ["x": .integer(Int64($0.x)), "y": .integer(Int64($0.y))] }
        return await toolkit.withPageContext(page: arguments.page, observationID: nil) {
            await toolkit.visualAction(name: name, action: ["type": "drag_events", "path": .array(path)])
        }
    }
}
