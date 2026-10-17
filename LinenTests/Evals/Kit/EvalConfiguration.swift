// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

@testable import Linen

nonisolated struct EvalVariant: Sendable {
    let name: String
    let apply: @MainActor @Sendable (@MainActor () async throws -> EvalAttempt) async throws -> EvalAttempt

    static let all: [String: EvalVariant] = [
        "default": .init(name: "default") { body in try await body() },
        "deferred": .init(name: "deferred") { body in
            try await OpenAIToolSearch.$isAllowed.withValue(false) {
                try await AgentToolDeferral.$mode.withValue(.always) { try await body() }
            }
        },
        "eager": .init(name: "eager") { body in
            try await OpenAIToolSearch.$isAllowed.withValue(false) {
                try await AgentToolDeferral.$mode.withValue(.never) { try await body() }
            }
        },
    ]
}

nonisolated struct EvalConfiguration: Sendable {
    let providerID: String
    let model: String?
    let suite: String
    let taskIDs: Set<String>?
    let attempts: Int
    let variants: [String]
    let effort: String
    let output: URL?
    let revision: String
    let dirty: Bool
    let foreground: Bool

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["LINEN_EVAL"] != nil
    }

    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Self {
        func list(_ key: String) -> [String]? {
            environment[key].map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        }
        return Self(
            providerID: environment["LINEN_EVAL_PROVIDER"] ?? "apple",
            model: environment["LINEN_EVAL_MODEL"].flatMap { $0.isEmpty ? nil : $0 },
            suite: environment["LINEN_EVAL_SUITE"] ?? "tools",
            taskIDs: list("LINEN_EVAL_TASKS").map(Set.init),
            attempts: max(1, Int(environment["LINEN_EVAL_ATTEMPTS"] ?? "") ?? 1),
            variants: list("LINEN_EVAL_VARIANTS") ?? ["default"],
            effort: environment["LINEN_EVAL_EFFORT"] ?? "low",
            output: environment["LINEN_EVAL_OUTPUT"].map { URL(fileURLWithPath: $0, isDirectory: true) },
            revision: environment["LINEN_EVAL_REVISION"] ?? "unknown",
            dirty: environment["LINEN_EVAL_DIRTY"] == "1",
            foreground: environment["LINEN_EVAL_FOREGROUND"] == "1"
        )
    }

    @MainActor
    func provider() throws -> Provider {
        guard let provider = ProviderCatalog.shared.provider(id: providerID) else {
            throw EvalError.unknownProvider(providerID)
        }
        return provider
    }
}

nonisolated enum EvalError: Error, CustomStringConvertible {
    case unknownProvider(String)
    case unknownVariant(String)
    case unknownSuite(String)
    case unavailable(String)

    var description: String {
        switch self {
        case .unknownProvider(let id):
            "Unknown provider “\(id)”. Use a provider ID such as apple, openai, anthropic, google or ollama."
        case .unknownVariant(let name):
            "Unknown variant “\(name)”. Known variants: \(EvalVariant.all.keys.sorted().joined(separator: ", "))."
        case .unknownSuite(let name):
            "Unknown suite “\(name)”. Known suites: \(EvalSuites.all.keys.sorted().joined(separator: ", "))."
        case .unavailable(let reason):
            "The provider is not available: \(reason)"
        }
    }
}
