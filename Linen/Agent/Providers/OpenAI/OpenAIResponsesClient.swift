// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation

nonisolated struct OpenAIResponsesClient: Sendable {
    let api: OpenAIAPI
    let model: String
    let binding: String
    var settings: OpenAIResponseSettings = .init()
    private let mcpAuthorization: [UUID: String]
    private let providerID: String
    private let oauthAuthorization: @Sendable (OpenAIMCPServer, String) async throws -> String

    init(endpoint: URL, apiKey: String, model: String, settings: OpenAIResponseSettings = .init(), transport: (any OpenAITransport)? = nil,
         providerID: String = "openai", authorization: (@Sendable (UUID) -> String?)? = nil,
         oauthAuthorization: (@Sendable (OpenAIMCPServer, String) async throws -> String)? = nil) {
        self.model = model
        self.providerID = providerID
        self.oauthAuthorization = oauthAuthorization ?? { server, providerID in
            try await OpenAIMCPOAuthManager.shared.accessToken(server: server, providerID: providerID)
        }
        let credentials = Dictionary(settings.mcpServers.compactMap { server -> (UUID, String)? in
            guard server.oauth == nil, server.requiresAuthorization,
                  let token = authorization?(server.id) ?? (authorization == nil ? CredentialStore.mcpAuthorization(providerID: providerID, serverID: server.id) : nil) else { return nil }
            return (server.id, token)
        }, uniquingKeysWith: { first, _ in first })
        self.mcpAuthorization = credentials
        let remoteIdentity = settings.mcpServers.isEmpty ? "" : "\u{0}mcp:" +
            ((try? OpenAIJSON.encode(settings.mcpServers).text()) ?? "") +
            credentials.keys.sorted(by: { $0.uuidString < $1.uuidString }).map { $0.uuidString + ":" + credentials[$0, default: ""] }.joined(separator: "\u{0}")
        let discoveryIdentity = settings.useToolSearch && OpenAIToolSearch.supports(model) ? "\u{0}tool-search:v1" : ""
        let shellTools = settings.hostedTools.filter { $0["type"] == "shell" }
        let shellIdentity = shellTools.isEmpty ? "" : "\u{0}hosted-shell:v1:" + ((try? OpenAIJSON.array(shellTools).text()) ?? "")
        self.binding = OpenAIConversationState.binding(endpoint: endpoint, model: model, credential: apiKey + remoteIdentity + discoveryIdentity + shellIdentity)
        self.settings = settings
        let http = OpenAIHTTPTransport(baseURL: endpoint, apiKey: apiKey)
        api = OpenAIAPI(transport: transport ?? (settings.useWebSocket ? OpenAIWebSocketTransport(http: http) : http))
    }

    func restoring(_ saved: OpenAIConversationState?) -> OpenAIConversationState {
        saved?.binding == binding ? saved! : OpenAIConversationState(binding: binding)
    }

    func body(state: OpenAIConversationState, instructions: String, tools: [OpenAIJSON], maxTokens: Int,
              oauthTokens: [UUID: String] = [:]) throws -> OpenAIJSON {
        try settings.validate()
        var body = settings.additionalParameters
        body["model"] = .string(model)
        body["input"] = .array(state.mcpRequestItems(toolsEnabled: !settings.mcpServers.isEmpty))
        let uncertain = !state.pendingMCPApprovals.intersection(state.mcpApprovalAttempts ?? [])
            .subtracting(OpenAIMCPExecutionScope.freshApprovals).isEmpty
            ? "\nA previously approved remote tool call has an unconfirmed outcome. Its approval cannot be reused. "
                + "Report the uncertainty, verify effects with read-only tools, and do not repeat the action automatically."
            : ""
        body["instructions"] = .string(instructions + uncertain)
        body["max_output_tokens"] = .integer(Int64(maxTokens))
        body["store"] = .bool(settings.store)
        if OpenAIModelSupport.reasoning(model) {
            if body["reasoning"].object == nil {
                body["reasoning"] = [:]
            }
            if body["reasoning"]["effort"] == .null {
                body["reasoning"]["effort"] = .string(settings.reasoningEffort)
            }
            if settings.reasoningSummary, body["reasoning"]["summary"] == .null {
                body["reasoning"]["summary"] = "auto"
            }
        }
        if OpenAIModelSupport.verbosity(model) {
            if body["text"].object == nil {
                body["text"] = [:]
            }
            if body["text"]["verbosity"] == .null {
                body["text"]["verbosity"] = .string(settings.verbosity)
            }
        }
        body["service_tier"] = .string(settings.serviceTier)
        var includes = body["include"].array ?? []
        if OpenAIModelSupport.reasoning(model), !includes.contains("reasoning.encrypted_content") {
            includes.append("reasoning.encrypted_content")
        }
        body["include"] = .array(includes)
        let local = OpenAIToolSearch.definitions(tools, enabled: settings.useToolSearch && OpenAIToolSearch.supports(model))
        body["tools"] = .array(try local + OpenAIHostedShell.definitions(settings.hostedTools, state: state) + remoteTools(oauthTokens: oauthTokens))
        return body
    }

    func remoteTools(oauthTokens: [UUID: String] = [:]) throws -> [OpenAIJSON] {
        try settings.mcpServers.map { try $0.definition(authorization: $0.oauth == nil ? mcpAuthorization[$0.id] : oauthTokens[$0.id]) }
    }

    @MainActor
    func respond(
        transcript: Transcript, prompt: String, images: [Transcript.ImageSegment], state: OpenAIConversationState,
        tools: [any Tool], maxTokens: Int, attachmentInput: OpenAIAttachmentInput? = nil,
        onText: @escaping @MainActor (String) -> Void,
        onProgress: @escaping @MainActor (String) -> Void = { _ in }
    ) async throws -> OpenAIModelStep {
        var entries = Array(transcript)
        entries.append(.prompt(.init(segments: [.text(.init(content: prompt))] + images.map { .image($0) })))
        var state = try state.synchronizing(Transcript(entries: entries), attachmentInput: attachmentInput)
        let definitions = try tools.map { tool -> OpenAIJSON in
            [
                "type": "function", "name": .string(tool.name), "description": .string(tool.description),
                "parameters": try OpenAISchema.strict(tool.parameters, dependencies: OpenAISchema.browserDependencies), "strict": true,
            ]
        }
        var oauthTokens: [UUID: String] = [:]
        for server in settings.mcpServers where server.oauth != nil {
            oauthTokens[server.id] = try await oauthAuthorization(server, providerID)
        }
        try Task.checkCancellation()
        let request = try body(state: state, instructions: OpenAIConversationState.instructions(transcript), tools: definitions,
                               maxTokens: maxTokens, oauthTokens: oauthTokens)
        state.mcpDestinations = Dictionary(settings.mcpServers.map { ($0.label, $0.destination) }, uniquingKeysWith: { first, _ in first })
        let streaming = OpenAIVisibleStream(onText: onText, onProgress: onProgress)
        let response = try await api.createResponse(request) { notification in await streaming.receive(notification) }
        let usage = OpenAIUsage(raw: response["usage"])
        guard response["status"].string == "completed" else {
            let kind: OpenAIFailure.Kind = response["error"]["code"].string == "context_length_exceeded" ? .contextLimit : .incomplete
            throw OpenAIFailure(kind: kind, usage: usage)
        }
        let output: (text: String, calls: [Transcript.ToolCall])
        do {
            output = try OpenAIModelStep.output(response, remoteTools: remoteTools(oauthTokens: oauthTokens), localDefinitions: request["tools"].array ?? [])
        } catch {
            throw OpenAIFailure(kind: (error as? OpenAIFailure)?.kind ?? .invalidResponse, usage: usage)
        }
        let previousCalls = Set(state.items.compactMap { item -> String? in
            if item["type"] == "function_call" || item["type"] == "shell_call" { return item["call_id"].string }
            if item["type"] == "mcp_approval_request" { return item["id"].string }
            return nil
        })
        guard output.calls.allSatisfy({ !previousCalls.contains($0.id) }) else { throw OpenAIFailure(kind: .invalidResponse, usage: usage) }
        let shellIDs = (response["output"].array ?? []).filter { $0["type"] == "shell_call" }.compactMap { $0["call_id"].string }
        guard shellIDs.allSatisfy({ id in !previousCalls.contains(id) && !output.calls.contains(where: { $0.id == id }) }) else {
            throw OpenAIFailure(kind: .invalidResponse, usage: usage)
        }
        if !output.text.isEmpty {
            entries.append(.response(.init(assetIDs: [], segments: [.text(.init(content: output.text))])))
        }
        if !output.calls.isEmpty {
            entries.append(.toolCalls(.init(output.calls)))
        }
        let transcript = Transcript(entries: entries)
        try state.received(response, transcript: transcript)
        guard state.pendingMCPApprovals.isDisjoint(with: OpenAIMCPExecutionScope.freshApprovals) else {
            throw OpenAIFailure(kind: .incomplete, usage: usage)
        }
        return .init(text: output.text, calls: output.calls, transcript: transcript, state: state,
                     firstTextMilliseconds: streaming.firstTextMilliseconds)
    }

    func compact(state: OpenAIConversationState, instructions: String) async throws -> OpenAIConversationState {
        let response = try await api.compact(["model": .string(model), "input": .array(state.items), "instructions": .string(instructions)])
        guard let items = response["output"].array, !items.isEmpty else { throw OpenAIFailure(kind: .invalidResponse) }
        var state = state
        state.items = items
        state.responseID = nil
        state.usage = .init(raw: response["usage"])
        state.contextTokens = state.usage?.output
        return state
    }
}

nonisolated struct OpenAIModelStep {
    let text: String
    let calls: [Transcript.ToolCall]
    let transcript: Transcript
    let state: OpenAIConversationState
    let firstTextMilliseconds: Int?

    static func output(_ response: OpenAIJSON, remoteTools: [OpenAIJSON] = [], localDefinitions: [OpenAIJSON] = []) throws -> (text: String, calls: [Transcript.ToolCall]) {
        try OpenAIHostedShell.validateOutput(response, definitions: localDefinitions)
        var text: [String] = []
        var calls: [Transcript.ToolCall] = []
        let passive: Set<String> = [
            "reasoning", "compaction", "web_search_call", "file_search_call", "code_interpreter_call",
            "image_generation_call", "mcp_list_tools", "mcp_call", "shell_call", "shell_call_output",
        ]
        for item in response["output"].array ?? [] {
            guard let type = item["type"].string else { throw OpenAIFailure(kind: .invalidResponse) }
            if type == "message" {
                for part in item["content"].array ?? [] {
                    if let value = part["text"].string ?? part["refusal"].string {
                        text.append(value)
                    }
                }
            } else if type == "function_call" {
                try OpenAIToolSearch.validateNamespace(item, definitions: localDefinitions)
                guard let id = item["call_id"].string, let name = item["name"].string, let arguments = item["arguments"].string,
                    !id.isEmpty, !name.isEmpty, !calls.contains(where: { $0.id == id })
                else { throw OpenAIFailure(kind: .invalidResponse) }
                calls.append(.init(id: id, toolName: name, arguments: try GeneratedContent(json: arguments)))
            } else if type == "computer_call" {
                throw OpenAIFailure(kind: .unsupportedAction)
            } else if type == "tool_search_call" || type == "tool_search_output" {
                try OpenAIToolSearch.validateHostedEvent(item)
            } else if type == "mcp_approval_request" {
                let server = remoteTools.first { $0["server_label"] == item["server_label"] }
                let approval = try OpenAIMCPApproval(item, destination: server?["server_url"].string ?? server?["connector_id"].string)
                try approval.validate(servers: remoteTools)
                guard !calls.contains(where: { $0.id == approval.id }) else { throw OpenAIFailure(kind: .invalidResponse) }
                calls.append(try approval.proposal())
            } else if !passive.contains(type) {
                throw OpenAIFailure(kind: .unsupportedAction)
            }
        }
        if text.isEmpty, calls.isEmpty, response["output"].array?.contains(where: {
            $0["type"] == "image_generation_call" && $0["result"].string?.isEmpty == false
        }) == true {
            text.append(String(localized: "Image generated."))
        }
        return (text.joined(separator: "\n"), calls)
    }
}

@MainActor
private final class OpenAIVisibleStream {
    var text = ""
    private let started = ContinuousClock.now
    private var lastPublished: ContinuousClock.Instant?
    private var lastProgressPublished: ContinuousClock.Instant?
    private var progressArguments: [Int: String] = [:]
    private(set) var firstTextMilliseconds: Int?
    let onText: @MainActor (String) -> Void
    let onProgress: @MainActor (String) -> Void
    init(onText: @escaping @MainActor (String) -> Void, onProgress: @escaping @MainActor (String) -> Void) {
        self.onText = onText
        self.onProgress = onProgress
    }
    func receive(_ event: OpenAIEvent) {
        if event.type == "response.output_item.added",
           event.payload["item"]["type"] == "function_call",
           event.payload["item"]["name"].string == UpdateProgressTool.toolName,
           let index = event.payload["output_index"].int {
            progressArguments[index] = event.payload["item"]["arguments"].string ?? ""
        } else if event.type == "response.function_call_arguments.delta",
                  let index = event.payload["output_index"].int,
                  let delta = event.payload["delta"].string,
                  var arguments = progressArguments[index] {
            guard arguments.count + delta.count <= 16_000 else { return }
            arguments += delta
            progressArguments[index] = arguments
            publishProgress(arguments)
        } else if event.type == "response.function_call_arguments.done",
                  let index = event.payload["output_index"].int,
                  progressArguments[index] != nil,
                  let arguments = event.payload["arguments"].string {
            publishProgress(arguments, force: true)
        } else if event.type == "response.output_text.delta", let delta = event.payload["delta"].string {
            text += delta
            let now = ContinuousClock.now
            if firstTextMilliseconds == nil, !delta.isEmpty {
                let elapsed = (now - started).components
                firstTextMilliseconds = Int(elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000)
            }
            if let lastPublished, now - lastPublished < .milliseconds(50) {
                return
            }
            lastPublished = now
            onText(text)
        }
    }

    private func publishProgress(_ arguments: String, force: Bool = false) {
        guard arguments.count <= 16_000,
              let message = OpenAIProgressMessage.partial(arguments) else { return }
        let visible = String(message.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_000))
        guard !visible.isEmpty else { return }
        let now = ContinuousClock.now
        if !force, let lastProgressPublished, now - lastProgressPublished < .milliseconds(50) { return }
        lastProgressPublished = now
        onProgress(visible)
    }
}
