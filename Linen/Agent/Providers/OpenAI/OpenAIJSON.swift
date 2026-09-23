// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum OpenAIJSON: Codable, Equatable, Sendable {
    case object([String:
        Self])
    case array([Self])
    case string(String)
    case integer(Int64)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([Self].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: Self].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    subscript(_ key: String) -> Self {
        get {
            object?[key] ?? .null
        }
        set {
            var values = object ?? [:]
            values[key] = newValue
            self = .object(values)
        }
    }

    var object: [String: Self]? {
        if case .object(let value) = self {
            value } else { nil
        }
    }
    var array: [Self]? {
        if case .array(let value) = self {
            value } else { nil
        }
    }
    var string: String? {
        if case .string(let value) = self {
            value } else { nil
        }
    }
    var int: Int? {
        if case .integer(let value) = self {
            Int(exactly: value) } else { nil
        }
    }
    var finiteNumber: Double? {
        switch self {
        case .integer(let value): Double(value)
        case .number(let value) where value.isFinite: value
        default: nil
        }
    }
    var bool: Bool? {
        if case .bool(let value) = self {
            value } else { nil
        }
    }

    static func decode(_ data: Data) throws -> Self {
        try JSONDecoder().decode(Self.self, from: data)
    }
    static func encode<T: Encodable>(_ value: T) throws -> Self {
        try decode(JSONEncoder().encode(value))
    }
    func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
    func text() throws -> String {
        String(decoding: try data(), as: UTF8.self)
    }
}

extension OpenAIJSON: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral {
    init(stringLiteral value: String) {
        self = .string(value)
    }
    init(integerLiteral value: Int64) {
        self = .integer(value)
    }
    init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
    init(arrayLiteral elements: Self...) {
        self = .array(elements)
    }
    init(dictionaryLiteral elements: (String, Self)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
    init(nilLiteral: ()) {
        self = .null
    }
}
