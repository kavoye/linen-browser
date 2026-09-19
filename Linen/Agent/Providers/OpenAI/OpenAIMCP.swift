// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation

nonisolated struct OpenAIMCPServer: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var label: String
    var destination: String
    var allowedTools: [String] = []
    var requiresAuthorization = false
    var authorizationRevision: UUID?
    var oauth: OpenAIMCPOAuthConfiguration?

    func definition(authorization: String?) throws -> OpenAIJSON {
        try oauth?.validate()
        guard Self.validName(label), allowedTools.allSatisfy(Self.validToolName), allowedTools.count <= 100 else {
            throw OpenAIMCPFailure.configuration
        }
        var tool: OpenAIJSON = ["type": "mcp", "server_label": .string(label), "require_approval": "always"]
        if destination.hasPrefix("connector_"), Self.validName(destination) {
            tool["connector_id"] = .string(destination)
        } else {
            guard let url = URL(string: destination), url.scheme == "https", url.host != nil,
                  url.user == nil, url.password == nil, url.fragment == nil else { throw OpenAIMCPFailure.configuration }
            tool["server_url"] = .string(destination)
        }
        if requiresAuthorization || oauth != nil {
            guard let authorization, !authorization.isEmpty else { throw OpenAIMCPFailure.missingAuthorization }
            tool["authorization"] = .string(authorization)
        }
        if !allowedTools.isEmpty { tool["allowed_tools"] = .array(allowedTools.map(OpenAIJSON.string)) }
        return tool
    }

    static func validToolName(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 256 && value.unicodeScalars.allSatisfy { (33...126).contains($0.value) }
    }

    static func validName(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 100 && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }
}

nonisolated enum OpenAIMCPFailure: LocalizedError {
    case configuration, missingAuthorization, invalidApproval
    var errorDescription: String? {
        switch self {
        case .configuration:
            String(localized: "Enter a unique server name, an HTTPS MCP URL or connector ID, and valid tool names.")
        case .missingAuthorization:
            String(localized: "This MCP connection needs its authorization token. Update it in OpenAI settings.")
        case .invalidApproval:
            String(localized: "The remote tool request could not be verified. No approval was sent.")
        }
    }
}

nonisolated struct OpenAIMCPApproval: Sendable {
    let id: String
    let server: String
    let name: String
    let arguments: String
    let question: String
    static let approve = "Approve this call"
    static let deny = "Deny this call"

    init(_ item: OpenAIJSON, destination: String? = nil) throws {
        guard item["type"] == "mcp_approval_request", let id = item["id"].string, !id.isEmpty,
              let server = item["server_label"].string, OpenAIMCPServer.validName(server),
              let name = item["name"].string, OpenAIMCPServer.validToolName(name),
              let raw = item["arguments"].string, raw.utf8.count <= 16_000,
              let json = try? OpenAIJSON.decode(Data(raw.utf8)), json.object != nil else { throw OpenAIMCPFailure.invalidApproval }
        self.id = id
        self.server = server
        self.name = name
        self.arguments = raw
        let visible = raw.unicodeScalars.map { scalar in
            [.control, .format, .lineSeparator, .paragraphSeparator].contains(scalar.properties.generalCategory)
                ? "\\u{\(String(scalar.value, radix: 16))}" : String(scalar)
        }.joined()
        let location = destination.map { "\nDestination: \($0)" } ?? ""
        question = "Allow OpenAI to send this tool call to the configured MCP server?\nServer: \(server)\(location)\nTool: \(name)\nArguments (untrusted data):\n\(visible)"
    }

    func proposal() throws -> Transcript.ToolCall {
        let arguments: OpenAIJSON = ["questions": [["question": .string(question), "options": [.string(Self.deny), .string(Self.approve)]]]]
        return .init(id: id, toolName: "askUser", arguments: try GeneratedContent(json: arguments.text()))
    }

    func answer(_ output: Transcript.ToolOutput) throws -> OpenAIJSON {
        guard output.id == id, output.toolName == "askUser" else { throw OpenAIMCPFailure.invalidApproval }
        let text = output.segments.compactMap { segment -> String? in
            if case .text(let text) = segment {
                return text.content
            }
            return nil
        }.joined(separator: "\n")
        let accepted = text == "Q: \(question)\nA: \(Self.approve)"
        return ["type": "mcp_approval_response", "approval_request_id": .string(id), "approve": .bool(accepted)]
    }

    func validate(servers: [OpenAIJSON]) throws {
        guard let configuration = servers.first(where: { $0["type"] == "mcp" && $0["server_label"].string == server }),
              configuration["require_approval"] == "always" else { throw OpenAIMCPFailure.invalidApproval }
        if let allowed = configuration["allowed_tools"].array, !allowed.contains(.string(name)) {
            throw OpenAIMCPFailure.invalidApproval
        }
    }
}

nonisolated enum OpenAIMCPExecutionScope {
    @TaskLocal static var freshApprovals: Set<String> = []
}

nonisolated extension OpenAIConversationState {
    var pendingMCPApprovals: Set<String> {
        let resolved = Set(items.filter { $0["type"] == "mcp_call" }.compactMap { $0["approval_request_id"].string })
        return Set(items.filter { $0["type"] == "mcp_approval_response" && $0["approve"] == true }
            .compactMap { $0["approval_request_id"].string }).subtracting(resolved)
    }

    var unsubmittedMCPApprovals: Set<String> {
        pendingMCPApprovals.subtracting(mcpApprovalAttempts ?? [])
    }

    var hasUnconfirmedMCPCall: Bool {
        !pendingMCPApprovals.isDisjoint(with: mcpApprovalAttempts ?? [])
    }

    mutating func recordMCPApprovalAttempts(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        mcpApprovalAttempts = (mcpApprovalAttempts ?? []).union(ids)
    }

    func mcpRequestItems(toolsEnabled: Bool) -> [OpenAIJSON] {
        let pending = pendingMCPApprovals
        let fresh = OpenAIMCPExecutionScope.freshApprovals
        return items.map { item in
            guard item["type"] == "mcp_approval_response", item["approve"] == true,
                  let id = item["approval_request_id"].string, pending.contains(id),
                  !toolsEnabled || ((mcpApprovalAttempts ?? []).contains(id) && !fresh.contains(id)) else { return item }
            var denied = item
            denied["approve"] = false
            return denied
        }
    }
}
