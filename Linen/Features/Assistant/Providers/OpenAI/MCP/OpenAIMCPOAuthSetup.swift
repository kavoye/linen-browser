// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct OpenAIMCPOAuthDiscovery: Equatable, Sendable {
    let resource: String
    let issuers: [String]
    let scope: String
}

@MainActor
struct OpenAIMCPOAuthSetup {
    let transport: any OpenAIMCPOAuthTransport

    init(transport: any OpenAIMCPOAuthTransport = OpenAIMCPOAuthHTTP()) {
        self.transport = transport
    }

    func discover(destination: String) async throws -> OpenAIMCPOAuthDiscovery {
        let target = try OpenAIMCPOAuthConfiguration.https(destination)
        var request = URLRequest(url: target)
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        let probe = try await transport.probe(request)
        try Task.checkCancellation()
        guard (200..<300).contains(probe.status) || [401, 404, 405].contains(probe.status) else { throw OpenAIMCPOAuthFailure.discovery }
        let header = probe.headers.first { $0.key.lowercased() == "www-authenticate" }?.value
        let challenge = try probe.status == 401 ? OpenAIMCPOAuthChallenge(header ?? "") : .init("")
        var candidates: [(URL, String)] = []
        if let location = challenge.parameters["resource_metadata"] {
            candidates = [(try OpenAIMCPOAuthConfiguration.https(location), destination)]
        } else {
            guard var components = URLComponents(url: target, resolvingAgainstBaseURL: false) else { throw OpenAIMCPOAuthFailure.discovery }
            let path = components.percentEncodedPath
            components.percentEncodedPath = "/.well-known/oauth-protected-resource" + path
            guard let specific = components.url else { throw OpenAIMCPOAuthFailure.discovery }
            candidates.append((specific, destination))
            components.percentEncodedPath = ""
            guard let origin = components.url?.absoluteString else { throw OpenAIMCPOAuthFailure.discovery }
            components.percentEncodedPath = "/.well-known/oauth-protected-resource"
            guard let root = components.url else { throw OpenAIMCPOAuthFailure.discovery }
            if root != specific {
                candidates.append((root, origin))
            }
        }
        for (url, expectedResource) in candidates {
            try Task.checkCancellation()
            let response = try await transport.send(URLRequest(url: url))
            if [404, 410].contains(response.status) {
                continue
            }
            guard (200..<300).contains(response.status), let json = try? OpenAIJSON.decode(response.data),
                  json["resource"].string == expectedResource,
                  let advertised = json["authorization_servers"].array, !advertised.isEmpty, advertised.count <= 10 else { throw OpenAIMCPOAuthFailure.discovery }
            let issuers = try advertised.map { item -> String in
                guard let issuer = item.string else { throw OpenAIMCPOAuthFailure.discovery }
                _ = try OpenAIMCPOAuthConfiguration.https(issuer)
                return issuer
            }
            let scope: String
            if let requested = challenge.parameters["scope"] {
                scope = try Self.scope(requested)
            } else if json["scopes_supported"] != .null {
                guard let scopes = json["scopes_supported"].array, scopes.count <= 100 else { throw OpenAIMCPOAuthFailure.discovery }
                scope = try Self.scope(scopes.map { item in
                    guard let value = item.string, !value.isEmpty, !value.contains(" ") else { throw OpenAIMCPOAuthFailure.discovery }
                    return value
                }.joined(separator: " "))
            } else {
                scope = ""
            }
            try Task.checkCancellation()
            return .init(resource: expectedResource, issuers: issuers.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }, scope: scope)
        }
        throw OpenAIMCPOAuthFailure.discovery
    }

    func register(issuer: String, scope: String, resource: String) async throws -> String {
        let configuration = OpenAIMCPOAuthConfiguration(issuer: issuer, clientID: "registration-pending", scope: try Self.scope(scope), resource: resource)
        let metadata = try await OpenAIMCPOAuthManager(transport: transport).discover(configuration)
        guard let endpoint = metadata.registration else { throw OpenAIMCPOAuthFailure.registrationUnavailable }
        var body: OpenAIJSON = ["client_name": "Linen", "application_type": "native",
                               "redirect_uris": [.string(OpenAIMCPOAuthConfiguration.redirect)],
                               "grant_types": metadata.supportsRefresh ? ["authorization_code", "refresh_token"] : ["authorization_code"],
                               "response_types": ["code"], "token_endpoint_auth_method": "none",
        ]
        if !scope.isEmpty { body["scope"] = .string(scope) }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try body.data()
        try Task.checkCancellation()
        let response = try await transport.send(request)
        try Task.checkCancellation()
        guard response.status == 201, let json = try? OpenAIJSON.decode(response.data),
              let clientID = json["client_id"].string,
              json["token_endpoint_auth_method"] == "none",
              json["client_secret"] == .null,
              json["redirect_uris"] == body["redirect_uris"],
              let grants = json["grant_types"].array, grants.contains("authorization_code"),
              grants.allSatisfy({ body["grant_types"].array?.contains($0) == true }),
              json["response_types"] == body["response_types"] else { throw OpenAIMCPOAuthFailure.registration }
        try OpenAIMCPOAuthConfiguration(issuer: issuer, clientID: clientID, scope: scope, resource: resource).validate()
        return clientID
    }

    private static func scope(_ value: String) throws -> String {
        guard value.utf8.count <= 4_096, value.unicodeScalars.allSatisfy({ $0.value == 32 || ((33...126).contains($0.value) && $0.value != 34 && $0.value != 92) })
        else { throw OpenAIMCPOAuthFailure.discovery }
        return value
    }
}

nonisolated struct OpenAIMCPOAuthChallenge {
    private(set) var parameters: [String: String] = [:]

    init(_ header: String) throws {
        var bearer = false, seen = false
        for raw in try Self.parts(header) {
            var value = raw.trimmingCharacters(in: .whitespaces)
            if value.isEmpty {
                continue
            }
            if let space = value.firstIndex(where: { $0 == " " || $0 == "\t" }),
               !value[..<space].contains("="), !value[space...].trimmingCharacters(in: .whitespaces).hasPrefix("=") {
                bearer = value[..<space].lowercased() == "bearer"
                value = value[space...].trimmingCharacters(in: .whitespaces)
                if bearer {
                    guard !seen else { throw OpenAIMCPOAuthFailure.discovery }
                    seen = true
                }
            } else if !value.contains("=") {
                bearer = value.lowercased() == "bearer"
                if bearer {
                    guard !seen else { throw OpenAIMCPOAuthFailure.discovery }
                    seen = true
                }
                continue
            }
            guard bearer else { continue }
            guard let equals = value.firstIndex(of: "=") else { throw OpenAIMCPOAuthFailure.discovery }
            let name = value[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let rawValue = value[value.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, name.allSatisfy(Self.token), parameters[name] == nil else { throw OpenAIMCPOAuthFailure.discovery }
            parameters[name] = try Self.decode(rawValue)
        }
    }

    private static func parts(_ header: String) throws -> [String] {
        guard header.utf8.count <= 16_384, !header.unicodeScalars.contains(where: { $0.value < 32 && $0.value != 9 }) else { throw OpenAIMCPOAuthFailure.discovery }
        var parts: [String] = [], part = "", quoted = false, escaped = false
        for character in header {
            if escaped {
                escaped = false; part.append(character); continue
            }
            if quoted && character == "\\" { escaped = true; part.append(character); continue }
            if character == "\"" { quoted.toggle() }
            if character == "," && !quoted { parts.append(part); part = "" } else { part.append(character) }
        }
        guard !quoted, !escaped else { throw OpenAIMCPOAuthFailure.discovery }
        parts.append(part)
        return parts
    }

    private static func decode(_ value: String) throws -> String {
        guard value.hasPrefix("\"") else {
            guard !value.isEmpty, value.allSatisfy(Self.token) else { throw OpenAIMCPOAuthFailure.discovery }
            return value
        }
        guard value.count >= 2, value.hasSuffix("\"") else { throw OpenAIMCPOAuthFailure.discovery }
        var decoded = "", escape = false
        for character in value.dropFirst().dropLast() {
            if escape {
                decoded.append(character); escape = false
            } else if character == "\\" {
                escape = true
            } else if character == "\"" {
                throw OpenAIMCPOAuthFailure.discovery
            } else {
                decoded.append(character)
            }
        }
        guard !escape else { throw OpenAIMCPOAuthFailure.discovery }
        return decoded
    }

    private static func token(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || "!#$%&'*+-.^_`|~".contains(character))
    }
}
