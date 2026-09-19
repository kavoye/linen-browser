// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation

nonisolated struct OpenAIComputerCall: Sendable {
    static let toolName = "__linen_openai_computer"
    let raw: OpenAIJSON
    let id: String
    let actions: [OpenAIJSON]
    let safetyChecks: [OpenAIJSON]

    init(_ raw: OpenAIJSON) throws {
        guard raw["type"] == "computer_call", raw["status"] == "completed",
              let id = raw["call_id"].string, !id.isEmpty else { throw OpenAIFailure(kind: .invalidResponse) }
        let actions: [OpenAIJSON]
        if let batch = raw["actions"].array, raw["action"] == .null {
            actions = batch
        } else if raw["actions"] == .null, raw["action"].object != nil {
            actions = [raw["action"]]
        } else { throw OpenAIFailure(kind: .invalidResponse) }
        guard !actions.isEmpty, actions.count <= 50 else { throw OpenAIFailure(kind: .invalidResponse) }
        for action in actions {
            try Self.validate(action)
        }
        let checks = raw["pending_safety_checks"].array ?? []
        guard raw["pending_safety_checks"] == .null || raw["pending_safety_checks"].array != nil,
              checks.count <= 20, checks.allSatisfy({ $0["id"].string?.isEmpty == false }),
              Set(checks.compactMap { $0["id"].string }).count == checks.count else { throw OpenAIFailure(kind: .invalidResponse) }
        self.raw = raw
        self.id = id
        self.actions = actions
        self.safetyChecks = checks
    }

    func proposal() throws -> Transcript.ToolCall {
        let arguments: OpenAIJSON = ["request": .string(try raw.text())]
        return .init(id: id, toolName: Self.toolName, arguments: try GeneratedContent(json: arguments.text()))
    }

    static func validate(_ action: OpenAIJSON) throws {
        func point(_ value: OpenAIJSON) throws {
            guard let x = number(value["x"]), let y = number(value["y"]), (0...32_768).contains(x), (0...32_768).contains(y) else {
                throw OpenAIFailure(kind: .invalidResponse)
            }
        }
        switch action["type"].string {
        case "click":
            try point(action)
            guard ["left", "right", "wheel", "back", "forward"].contains(action["button"].string ?? "") else { throw OpenAIFailure(kind: .invalidResponse) }
        case "double_click", "move":
            try point(action)
        case "scroll":
            try point(action)
            guard let x = number(action["scroll_x"]), let y = number(action["scroll_y"]), (-32_768...32_768).contains(x), (-32_768...32_768).contains(y) else {
                throw OpenAIFailure(kind: .invalidResponse)
            }
        case "drag":
            guard let path = action["path"].array, (2...500).contains(path.count) else { throw OpenAIFailure(kind: .invalidResponse) }
            for position in path {
                try point(position)
            }
        case "type":
            guard let text = action["text"].string, text.utf8.count <= 100_000 else { throw OpenAIFailure(kind: .invalidResponse) }
        case "keypress":
            guard let keys = action["keys"].array, (1...5).contains(keys.count), keys.allSatisfy({ $0.string?.isEmpty == false }) else {
                throw OpenAIFailure(kind: .invalidResponse)
            }
        case "wait", "screenshot":
            break
        default:
            throw OpenAIFailure(kind: .unsupportedAction)
        }
        if action["type"] != "keypress", action["keys"] != .null {
            let modifiers: Set<String> = ["SHIFT", "ALT", "OPTION", "CTRL", "CONTROL", "META", "CMD", "COMMAND"]
            guard let keys = action["keys"].array, keys.count <= 4,
                  keys.allSatisfy({ modifiers.contains($0.string?.uppercased() ?? "") }) else { throw OpenAIFailure(kind: .unsupportedAction) }
        }
    }

    static func number(_ value: OpenAIJSON) -> Double? {
        if let integer = value.int {
            return Double(integer)
        }
        if case .number(let number) = value, number.isFinite {
            return number
        }
        return nil
    }

    func result(_ output: Transcript.ToolOutput) throws -> OpenAIJSON? {
        guard let text = output.segments.compactMap({ if case .text(let value) = $0 { value.content } else { nil } }).first,
              let metadata = try? OpenAIJSON.decode(Data(text.utf8)), metadata["success"] == true,
              safetyChecks.isEmpty || metadata["safety_approved"] == true,
              let image = output.segments.compactMap({ if case .image(let value) = $0 { value } else { nil } }).first else { return nil }
        guard case .data(let data, let mime) = image.source, !data.isEmpty, ["image/jpeg", "image/png"].contains(mime) else {
            throw OpenAIFailure(kind: .invalidResponse)
        }
        var result: OpenAIJSON = ["type": "computer_call_output", "call_id": .string(id), "output": [
            "type": "computer_screenshot", "image_url": .string("data:\(mime);base64," + data.base64EncodedString()), "detail": "original",
        ], ]
        if !safetyChecks.isEmpty {
            result["acknowledged_safety_checks"] = .array(safetyChecks)
        }
        return result
    }
}

nonisolated struct OpenAIComputerTool: Tool {
    let name = OpenAIComputerCall.toolName
    let description = "Execute a native OpenAI computer action in the authorized browser page."
    let toolkit: AgentToolkit
    @Generable struct Arguments {
        var request: String
    }
    func call(arguments: Arguments) async throws -> String {
        try await toolkit.computerCall(OpenAIComputerCall(.decode(Data(arguments.request.utf8))))
    }
}
