// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import CryptoKit
import Foundation

nonisolated struct OpenAIConversationState: Codable, Equatable, Sendable {
    let binding: String
    var items: [OpenAIJSON] = []
    var anchor: [String] = []
    var responseID: String?
    var contextTokens: Int?
    var usage: OpenAIUsage?
    var presentation: OpenAIPresentation?
    var mcpDestinations: [String: String]?
    var mcpApprovalAttempts: Set<String>?
    var shellContainerID: String?

    func synchronizing(_ transcript: Transcript, attachmentInput: OpenAIAttachmentInput? = nil) throws -> Self {
        let entries = transcript.filter { if case .instructions = $0 { false } else { true } }
        let hashes = try entries.map(Self.hash)
        guard hashes.starts(with: anchor) else { throw OpenAIFailure(kind: .invalidResponse) }
        var copy = self
        var added: [OpenAIJSON] = []
        for entry in entries.dropFirst(anchor.count) {
            if case .toolOutput(let output) = entry,
               let request = copy.items.first(where: { $0["type"] == "mcp_approval_request" && $0["id"].string == output.id }) {
                guard !(copy.items + added).contains(where: { $0["type"] == "mcp_approval_response" && $0["approval_request_id"].string == output.id }) else {
                    throw OpenAIMCPFailure.invalidApproval
                }
                added.append(try OpenAIMCPApproval(request, destination: copy.mcpDestinations?[request["server_label"].string ?? ""]).answer(output))
            } else {
                added += try Self.items(entry)
            }
        }
        if let attachmentInput {
            guard case .prompt = entries.last, added.last?["role"] == "user" else {
                throw OpenAIFailure(kind: .invalidResponse)
            }
            added[added.count - 1]["content"] = .array(attachmentInput.content)
        }
        copy.items += added
        copy.anchor = hashes
        if let tokens = copy.contextTokens {
            copy.contextTokens = tokens + (try OpenAIJSON.array(added).data().count) / 3
        }
        return copy
    }

    mutating func received(_ response: OpenAIJSON, transcript: Transcript) throws {
        guard let output = response["output"].array else { throw OpenAIFailure(kind: .invalidResponse) }
        items += output
        if let shell = output.last(where: { $0["type"] == "shell_call" && $0["status"] == "completed" }),
           shell["environment"]["type"] == "container_reference", let id = shell["environment"]["container_id"].string, !id.isEmpty {
            shellContainerID = id
        }
        responseID = response["id"].string
        usage = .init(raw: response["usage"])
        var visible = presentation ?? .init()
        visible.append(response)
        presentation = visible
        if let input = usage?.input, let output = usage?.output {
            contextTokens = input + output
        }
        anchor = try transcript.filter { if case .instructions = $0 { false } else { true } }.map(Self.hash)
    }

    static func binding(endpoint: URL, model: String, credential: String = "") -> String {
        SHA256.hash(data: Data((endpoint.absoluteString + "\u{0}" + model + "\u{0}" + credential).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    private static func hash(_ entry: Transcript.Entry) throws -> String {
        let data = try OpenAIJSON.encode(entry).data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func items(_ entry: Transcript.Entry) throws -> [OpenAIJSON] {
        switch entry {
        case .instructions:
            return []
        case .prompt(let value):
            return [["role": "user", "content": .array(content(value.segments))]]
        case .response(let value):
            return [["role": "assistant", "content": .array(content(value.segments))]]
        case .toolCalls(let calls):
            return calls.map {
                [
                    "type": "function_call", "call_id": .string($0.id), "name": .string($0.toolName),
                    "arguments": .string($0.arguments.jsonString),
                ]
            }
        case .toolOutput(let value):
            return [["type": "function_call_output", "call_id": .string(value.id), "output": .array(content(value.segments))]]
        }
    }

    static func content(_ segments: [Transcript.Segment]) -> [OpenAIJSON] {
        segments.compactMap { segment in
            switch segment {
            case .text(let value):
                return ["type": "input_text", "text": .string(value.content)]
            case .image(let image):
                let url: String
                switch image.source {
                case .data(let data, let mime):
                    url = "data:\(mime);base64," + data.base64EncodedString()
                case .url(let value):
                    url = value.absoluteString
                }
                return ["type": "input_image", "image_url": .string(url)]
            default:
                return nil
            }
        }
    }

    static func instructions(_ transcript: Transcript) -> String {
        transcript.compactMap { entry in
            if case .instructions(let value) = entry {
                return value.segments.compactMap { if case .text(let text) = $0 { text.content } else { nil } }.joined(separator: "\n")
            }
            return nil
        }.joined(separator: "\n")
    }
}
