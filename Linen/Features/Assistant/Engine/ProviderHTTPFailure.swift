// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import HTTPTypes

nonisolated struct ProviderHTTPFailure {
    let status: Int?
    let codes: Set<String>
    let message: String
    let retryAfter: Double?

    private static let quotaCodes: Set<String> = ["insufficient_quota", "billing_hard_limit_reached"]
    private static let rateLimitCodes: Set<String> = ["rate_limit_error", "rate_limit_exceeded", "RESOURCE_EXHAUSTED"]
    private static let transientCodes: Set<String> = ["overloaded_error", "api_error", "server_error", "UNAVAILABLE"]
    private static let contextCodes: Set<String> = ["context_length_exceeded", "exceed_context_size_error"]
    private static let contextPhrases = [
        "prompt is too long", "maximum context length", "exceeds the maximum number of tokens",
        "exceeds the available context size", "context window",
    ]

    init?(_ error: any Error) {
        guard let error = error as? HTTPTransportError,
              error.kind == .httpError || error.kind == .providerError else { return nil }
        status = error.kind == .httpError ? error.response?.status.code : nil
        let json = error.body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let detail = json?["error"] as? [String: Any]
        codes = Set([detail?["code"], detail?["type"], detail?["status"]].compactMap { $0 as? String })
        message = ((detail?["message"] ?? json?["message"]) as? String ?? "").lowercased()
        let fields = error.response?.headerFields
        retryAfter = AgentProviderRetry.retryAfter(
            fields?[.retryAfter], milliseconds: HTTPField.Name("retry-after-ms").flatMap { fields?[$0] })
    }

    var isRateLimited: Bool {
        codes.isDisjoint(with: Self.quotaCodes) && (status == 429 || !codes.isDisjoint(with: Self.rateLimitCodes))
    }

    var isTransient: Bool {
        guard codes.isDisjoint(with: Self.quotaCodes) else { return false }
        return isRateLimited || [500, 502, 503, 504, 529].contains(status ?? 0) || !codes.isDisjoint(with: Self.transientCodes)
    }

    var isContextOverflow: Bool {
        guard status == nil || status == 400 || status == 413 else { return false }
        return !codes.isDisjoint(with: Self.contextCodes) || Self.contextPhrases.contains { message.contains($0) }
    }
}
