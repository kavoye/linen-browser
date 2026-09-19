// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation

nonisolated enum OpenAISchema {
    static let browserDependencies = [AskUserTool.Question.generationSchema, FillFieldsTool.Field.generationSchema]

    static func wrappedValue<T: Generable>(_ type: T.Type) throws -> OpenAIJSON {
        let dependencies = (type as? any OpenAIArraySchema.Type)?.elementSchemas ?? []
        var value = try strict(type.generationSchema, dependencies: dependencies).object ?? [:]
        let definitions = value.removeValue(forKey: "$defs")
        var root: OpenAIJSON = ["type": "object", "properties": ["value": .object(value)],
                                "required": ["value"], "additionalProperties": false, ]
        if let definitions {
            root["$defs"] = definitions
        }
        return root
    }

    static func strict(_ schema: GenerationSchema, dependencies: [GenerationSchema] = []) throws -> OpenAIJSON {
        var root = try resolvingDefinitions(OpenAIJSON.encode(schema), dependencies: dependencies)
        if let reference = root["$ref"].string, reference.hasPrefix("#/$defs/"),
            let definition = root["$defs"][String(reference.dropFirst(8))].object {
            let definitions = root["$defs"]
            root = .object(definition)
            root["$defs"] = definitions
        }
        return strict(root)
    }

    private static func resolvingDefinitions(_ encoded: OpenAIJSON, dependencies: [GenerationSchema]) throws -> OpenAIJSON {
        var root = encoded
        var definitions = root["$defs"].object ?? [:]
        var available: [String: OpenAIJSON] = [:]
        for dependency in dependencies {
            let schema = try OpenAIJSON.encode(dependency)
            available.merge(schema["$defs"].object ?? [:]) { first, _ in first }
        }
        var resolved: Set<String> = []
        while true {
            let missing = references(in: root).subtracting(definitions.keys)
            guard !missing.isEmpty else { return root }
            guard resolved.count + missing.count <= 256, resolved.isDisjoint(with: missing) else {
                throw OpenAIFailure(kind: .configuration)
            }
            for name in missing {
                guard let definition = available[name] else { throw OpenAIFailure(kind: .configuration) }
                definitions[name] = definition
                resolved.insert(name)
            }
            root["$defs"] = .object(definitions)
        }
    }

    static func references(in value: OpenAIJSON) -> Set<String> {
        var found: Set<String> = []
        if let reference = value["$ref"].string, reference.hasPrefix("#/$defs/") {
            found.insert(String(reference.dropFirst(8)))
        }
        for child in value.object?.values ?? [:].values {
            found.formUnion(references(in: child))
        }
        for child in value.array ?? [] {
            found.formUnion(references(in: child))
        }
        return found
    }

    static func strict(_ value: OpenAIJSON) -> OpenAIJSON {
        guard var object = value.object else {
            if let array = value.array {
                return .array(array.map(strict))
            }
            return value
        }
        for key in ["$defs", "definitions"] {
            if let definitions = object[key]?.object {
                object[key] = .object(definitions.mapValues(strict))
            }
        }
        if let properties = object["properties"]?.object {
            let required = Set(object["required"]?.array?.compactMap(\.string) ?? [])
            object["properties"] = .object(
                properties.mapValues(strict).reduce(into: [:]) { result, entry in
                    result[entry.key] = required.contains(entry.key) ? entry.value : ["anyOf": [entry.value, ["type": "null"]]]
                })
            object["required"] = .array(properties.keys.sorted().map { .string($0) })
            object["additionalProperties"] = false
        }
        for key in ["items", "anyOf", "oneOf", "allOf"] {
            if let child = object[key] {
                object[key] = strict(child)
            }
        }
        return .object(object)
    }
}

private nonisolated protocol OpenAIArraySchema {
    static var elementSchemas: [GenerationSchema] { get }
}

extension Array: OpenAIArraySchema where Element: Generable {
    static var elementSchemas: [GenerationSchema] {
        [Element.generationSchema] + ((Element.self as? any OpenAIArraySchema.Type)?.elementSchemas ?? [])
    }
}
