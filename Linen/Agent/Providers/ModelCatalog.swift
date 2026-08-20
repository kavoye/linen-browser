// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum ModelCatalog {
    private static let excluded = [
        "embedding", "embed", "moderation", "tts", "whisper", "transcribe",
        "audio", "realtime", "image", "dall-e", "sora", "rerank", "guard",
    ]

    static func fetch(for provider: Provider, apiKey: String?) async throws -> [String] {
        guard let endpoint = provider.url(path: "models") else {
            throw ModelCatalogError.misconfigured(String(localized: "This provider has no endpoint set."))
        }

        var request = URLRequest(url: endpoint, timeoutInterval: provider.isLocal ? 5 : 15)
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ModelCatalogTransport.describe(error, endpoint: provider.endpointLabel)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw ModelCatalogError.http(
                status: status,
                message: ModelCatalogTransport.errorMessage(from: data)
            )
        }
        return try modelIDs(from: data, for: provider)
    }

    static func modelIDs(from data: Data, for provider: Provider) throws -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["data"] as? [[String: Any]]
        else {
            throw ModelCatalogError.malformedResponse
        }

        let ids = entries
            .compactMap { entry -> (id: String, created: Int)? in
                guard let id = entry["id"] as? String else { return nil }
                guard provider.isLocal || isTextModel(id) else { return nil }
                return (id, entry["created"] as? Int ?? 0)
            }

        if ids.contains(where: { $0.created > 0 }) {
            return ids.sorted { $0.created > $1.created }.map(\.id)
        }
        return ids.map(\.id).sorted()
    }

    private static func isTextModel(_ id: String) -> Bool {
        let lower = id.lowercased()
        return !excluded.contains { lower.contains($0) }
    }
}

nonisolated enum ModelCatalogError: LocalizedError {
    case http(status: Int, message: String)
    case malformedResponse
    case notReachable(String)
    case misconfigured(String)

    var errorDescription: String? {
        switch self {
        case .http(let status, let message):
            String(localized: "Provider error \(status): \(message)")
        case .malformedResponse:
            String(localized: "Unexpected response from the provider")
        case .notReachable(let endpoint):
            String(localized: "Couldn’t reach \(endpoint)")
        case .misconfigured(let reason):
            reason
        }
    }
}

nonisolated private enum ModelCatalogTransport {
    static func errorMessage(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            return raw.isEmpty ? String(localized: "unknown") : String(raw.prefix(200))
        }
        if let object = json["error"] as? [String: Any],
           let message = object["message"] as? String {
            return message
        }
        if let message = json["error"] as? String {
            return message
        }
        if let message = json["message"] as? String {
            return message
        }
        return String(localized: "unknown")
    }

    static func describe(_ error: any Error, endpoint: String) -> any Error {
        guard let urlError = error as? URLError else { return error }
        switch urlError.code {
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .timedOut:
            return ModelCatalogError.notReachable(endpoint)
        default:
            return error
        }
    }
}
