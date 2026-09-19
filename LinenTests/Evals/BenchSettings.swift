// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

@testable import Linen

struct BenchSettings: Decodable {
    enum SearchMode: String, Decodable { case disabled, live }
    var reasoningEffort = "low"
    var headless = false
    var searchMode = SearchMode.disabled
    var maxModelRequests: Int?
    var toolSearch = false
    var computerUse = false

    init() {}

    func openAIOptions(model: String, adapter: Provider.Adapter) throws -> OpenAIResponseSettings {
        if toolSearch, adapter != .openAIResponses || !OpenAIToolSearch.supports(model) {
            throw ConfigurationError.unsupportedToolSearch
        }
        if computerUse, adapter != .openAIResponses || headless {
            throw ConfigurationError.unsupportedComputerUse
        }
        var options = OpenAIResponseSettings()
        options.useToolSearch = toolSearch
        options.useComputer = computerUse
        return options
    }

    enum ConfigurationError: Error { case unsupportedToolSearch, unsupportedComputerUse }

    init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: Field.self)
        let allowed: Set<String> = ["reasoningEffort", "headless", "searchMode", "maxModelRequests", "toolSearch", "computerUse"]
        guard fields.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unsupported benchmark setting"))
        }
        reasoningEffort = try fields.decodeIfPresent(String.self, forKey: Field("reasoningEffort")) ?? "low"
        headless = try fields.decodeIfPresent(Bool.self, forKey: Field("headless")) ?? false
        searchMode = try fields.decodeIfPresent(SearchMode.self, forKey: Field("searchMode")) ?? .disabled
        maxModelRequests = try fields.decodeIfPresent(Int.self, forKey: Field("maxModelRequests"))
        toolSearch = try fields.decodeIfPresent(Bool.self, forKey: Field("toolSearch")) ?? false
        computerUse = try fields.decodeIfPresent(Bool.self, forKey: Field("computerUse")) ?? false
        if let maxModelRequests, !(1...500).contains(maxModelRequests) {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Model request limit must be between 1 and 500"))
        }
    }

    private struct Field: CodingKey {
        let stringValue: String
        var intValue: Int? {
            nil
        }
        init(_ value: String) {
            stringValue = value
        }
        init?(stringValue: String) {
            self.init(stringValue)
        }
        init?(intValue: Int) {
            return nil
        }
    }
}
