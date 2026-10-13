// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct OpenAIResponseSettings: Codable, Equatable, Sendable {
    var reasoningEffort = "low"
    var verbosity = "low"
    var serviceTier = "auto"
    var store = false
    var reasoningSummary = false
    var useWebSocket = false
    var useToolSearch = false
    var voice = OpenAIVoiceSettings()
    var hostedTools: [OpenAIJSON] = []
    var mcpServers: [OpenAIMCPServer] = []
    var additionalParameters: OpenAIJSON = [:]

    init() {}

    private enum CodingKeys: String, CodingKey {
        case reasoningEffort, verbosity, serviceTier, store, reasoningSummary, useWebSocket, useToolSearch, voice, hostedTools, mcpServers, additionalParameters
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        reasoningEffort = try values.decodeIfPresent(String.self, forKey: .reasoningEffort) ?? "low"
        verbosity = try values.decodeIfPresent(String.self, forKey: .verbosity) ?? "low"
        serviceTier = try values.decodeIfPresent(String.self, forKey: .serviceTier) ?? "auto"
        store = try values.decodeIfPresent(Bool.self, forKey: .store) ?? false
        reasoningSummary = try values.decodeIfPresent(Bool.self, forKey: .reasoningSummary) ?? false
        useWebSocket = try values.decodeIfPresent(Bool.self, forKey: .useWebSocket) ?? false
        useToolSearch = try values.decodeIfPresent(Bool.self, forKey: .useToolSearch) ?? false
        voice = try values.decodeIfPresent(OpenAIVoiceSettings.self, forKey: .voice) ?? .init()
        mcpServers = try values.decodeIfPresent([OpenAIMCPServer].self, forKey: .mcpServers) ?? []
        hostedTools = try values.decodeIfPresent([OpenAIJSON].self, forKey: .hostedTools) ?? []
        additionalParameters = try values.decodeIfPresent(OpenAIJSON.self, forKey: .additionalParameters) ?? [:]
    }

    func validate() throws {
        guard let parameters = additionalParameters.object else { throw OpenAISettingsError.objectRequired }
        let reserved: Set<String> = [
            "model", "input", "instructions", "tools", "max_output_tokens", "store", "service_tier",
            "previous_response_id", "conversation", "background", "stream", "agent", "stream_id", "type", "generate",
        ]
        guard reserved.isDisjoint(with: parameters.keys) else { throw OpenAISettingsError.managedField }
        for key in ["reasoning", "text"] {
            if let value = parameters[key], value.object == nil {
                throw OpenAISettingsError.objectRequired
            }
        }
        if let includes = parameters["include"], includes.array?.allSatisfy({ $0.string != nil }) != true {
            throw OpenAISettingsError.invalidInclude
        }
        guard mcpServers.count <= 20, Set(mcpServers.map(\.label)).count == mcpServers.count,
              Set(mcpServers.map(\.id)).count == mcpServers.count else { throw OpenAIMCPFailure.configuration }
        for server in mcpServers { _ = try server.definition(authorization: server.requiresAuthorization || server.oauth != nil ? "validation-only" : nil) }
        let supported: Set<String> = ["web_search", "web_search_preview", "code_interpreter", "image_generation", "shell"]
        guard hostedTools.allSatisfy({ supported.contains($0["type"].string ?? "") }) else { throw OpenAISettingsError.unsupportedTool }
        let shells = hostedTools.filter { $0["type"] == "shell" }
        guard shells.count <= 1 else { throw OpenAISettingsError.shellEnvironment }
        for shell in shells {
            try OpenAIHostedShell.validate(shell)
        }
    }
}

nonisolated enum OpenAISettingsError: LocalizedError {
    case objectRequired, managedField, invalidInclude, unsupportedTool, shellEnvironment
    var errorDescription: String? {
        switch self {
        case .objectRequired:
            String(localized: "Enter a JSON object. Reasoning and text options must also be objects.")
        case .managedField:
            String(
                localized:
                    "Linen manages model, input, instructions, tools, output limits, storage, service tier, and continuation fields. Use the controls for these settings."
            )
        case .invalidInclude:
            String(localized: "The include option must be an array of strings.")
        case .unsupportedTool:
            String(localized: "Supported hosted tools are web search, file search, code interpreter, image generation, and hosted shell.")
        case .shellEnvironment:
            String(localized: "Configure one hosted shell with an automatic container or an existing container ID. Local shell execution is not supported.")
        }
    }
}

nonisolated enum OpenAIModelSupport {
    static func reasoning(_ model: String) -> Bool {
        let id = model.lowercased()
        return ["gpt-5", "gpt-6", "o1", "o3", "o4"].contains(where: id.hasPrefix)
    }
    static func verbosity(_ model: String) -> Bool {
        let id = model.lowercased()
        return id.hasPrefix("gpt-5") || id.hasPrefix("gpt-6")
    }
}

enum OpenAISettingsStore {
    @TaskLocal static var scoped: OpenAIResponseSettings?
    static func load(providerID: String) -> OpenAIResponseSettings {
        if let scoped {
            return scoped
        }
        guard let data = UserDefaults.standard.data(forKey: "openai.options." + providerID),
            let settings = try? JSONDecoder().decode(OpenAIResponseSettings.self, from: data)
        else { return .init() }
        return settings
    }
    static func save(_ settings: OpenAIResponseSettings, providerID: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(settings), forKey: "openai.options." + providerID)
    }
}
