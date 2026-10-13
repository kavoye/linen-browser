// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum OpenAIHostedShell {
    static let definition: OpenAIJSON = ["type": "shell", "environment": ["type": "container_auto"]]

    static func validate(_ tool: OpenAIJSON) throws {
        let environment = tool["environment"]
        switch environment["type"].string {
        case "container_auto":
            break
        case "container_reference":
            guard environment["container_id"].string?.isEmpty == false else { throw OpenAISettingsError.shellEnvironment }
        default:
            throw OpenAISettingsError.shellEnvironment
        }
    }

    static func definitions(_ tools: [OpenAIJSON], state: OpenAIConversationState) -> [OpenAIJSON] {
        tools.map { tool in
            let previous = state.items.last(where: {
                      $0["type"] == "shell_call" && $0["status"] == "completed"
                          && $0["environment"]["type"] == "container_reference"
                  })
            guard tool["type"] == "shell", tool["environment"]["type"] == "container_auto",
                  let id = state.shellContainerID ?? previous?["environment"]["container_id"].string, !id.isEmpty else { return tool }
            var tool = tool
            tool["environment"] = ["type": "container_reference", "container_id": .string(id)]
            return tool
        }
    }

    static func validateOutput(_ response: OpenAIJSON, definitions: [OpenAIJSON]) throws {
        let items = response["output"].array ?? []
        let calls = items.filter { $0["type"] == "shell_call" }
        let outputs = items.filter { $0["type"] == "shell_call_output" }
        guard !calls.isEmpty || !outputs.isEmpty else { return }
        let tools = definitions.filter { $0["type"] == "shell" }
        guard tools.count == 1, let tool = tools.first else { throw OpenAIFailure(kind: .unsupportedAction) }
        try validate(tool)
        var identities: Set<String> = []
        for call in calls {
            guard call["status"] == "completed",
                  let id = call["call_id"].string, !id.isEmpty, identities.insert(id).inserted,
                  let commands = call["action"]["commands"].array, !commands.isEmpty,
                  commands.allSatisfy({ $0.string != nil }) else { throw OpenAIFailure(kind: .invalidResponse) }
            if call["environment"] != .null {
                guard call["environment"]["type"] == "container_reference",
                      call["environment"]["container_id"].string?.isEmpty == false else { throw OpenAIFailure(kind: .invalidResponse) }
                if tool["environment"]["type"] == "container_reference",
                   call["environment"]["container_id"] != tool["environment"]["container_id"] {
                    throw OpenAIFailure(kind: .invalidResponse)
                }
            }
        }
        var results: Set<String> = []
        for output in outputs {
            guard output["status"] == "completed", let id = output["call_id"].string,
                  identities.contains(id), results.insert(id).inserted,
                  let chunks = output["output"].array, !chunks.isEmpty else { throw OpenAIFailure(kind: .invalidResponse) }
            for chunk in chunks {
                let outcome = chunk["outcome"]
                guard chunk["stdout"].string != nil, chunk["stderr"].string != nil,
                      outcome["type"] == "timeout" || (outcome["type"] == "exit" && outcome["exit_code"].int != nil)
                else { throw OpenAIFailure(kind: .invalidResponse) }
            }
        }
        guard identities == results else { throw OpenAIFailure(kind: .incomplete) }
    }
}
