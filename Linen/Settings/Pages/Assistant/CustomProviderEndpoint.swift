// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum CustomProviderEndpoint {
    enum Problem: Error {
        case missingName
        case invalidURL
        case insecure

        var message: String {
            switch self {
            case .missingName:
                String(localized: "Enter a name.")
            case .invalidURL:
                String(localized: "This isn’t a valid URL. Try http://localhost:8000/v1")
            case .insecure:
                String(localized: "Use HTTPS to encrypt your API key. HTTP is allowed only for localhost.")
            }
        }
    }

    static func canConfigure(name: String, baseURL: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && normalizedURL(baseURL) != nil
    }

    static func configure(_ draft: Provider, name: String, baseURL: String) throws(Problem) -> Provider {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw .missingName }
        guard let url = normalizedURL(baseURL) else { throw .invalidURL }
        guard !isInsecureRemote(url) else { throw .insecure }
        var draft = draft
        draft.name = name
        draft.baseURL = url
        draft.isLocal = isLocalNetwork(url)
        draft.auth = draft.isLocal ? .none : .bearer
        let host = url.host() ?? ""
        draft.blurb = String(localized: "OpenAI-compatible endpoint at \(host)")
        return draft
    }

    static func normalizedURL(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") {
            text = "http://" + text
        }
        while text.hasSuffix("/") {
            text.removeLast()
        }
        if text.hasSuffix("/chat/completions") {
            text.removeLast("/chat/completions".count)
        }
        guard let url = URL(string: text), url.host() != nil else { return nil }
        return url
    }

    static func isLocalNetwork(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        return isLoopback(url) || host.hasSuffix(".local")
    }

    static func isLoopback(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    static func isInsecureRemote(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "http" && !isLoopback(url)
    }
}
