// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation
import Security

nonisolated struct OpenAIMCPOAuthConfiguration: Codable, Equatable, Sendable {
    var issuer: String
    var clientID: String
    var scope: String
    var resource: String = ""
    static let redirect = "com.kavoye.linen.oauth://callback"

    func validate() throws {
        _ = try Self.https(issuer)
        guard !clientID.isEmpty, clientID.utf8.count <= 2_048, scope.utf8.count <= 4_096,
              !(clientID + scope).unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { throw OpenAIMCPOAuthFailure.configuration }
        if !resource.isEmpty {
            _ = try Self.https(resource)
        }
    }

    static func https(_ text: String) throws -> URL {
        guard let url = URL(string: text), url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { throw OpenAIMCPOAuthFailure.configuration }
        return url
    }

    func metadataURLs() throws -> [URL] {
        try validate()
        var oauth = try URLComponents(url: Self.https(issuer), resolvingAgainstBaseURL: false).unwrap()
        let path = oauth.percentEncodedPath
        oauth.percentEncodedPath = "/.well-known/oauth-authorization-server" + path
        var inserted = oauth
        inserted.percentEncodedPath = "/.well-known/openid-configuration" + path
        let oidc = issuer.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/.well-known/openid-configuration"
        let candidates = [try oauth.url.unwrap(), try inserted.url.unwrap(), try URL(string: oidc).unwrap()]
        return candidates.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    func binding(destination: String) throws -> String {
        let data = try OpenAIJSON.encode(self).data()
        return SHA256.hash(data: data + Data(("\u{0}" + destination).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

nonisolated struct OpenAIMCPOAuthMetadata: Sendable {
    let issuer: String
    let authorization: URL
    let token: URL
    let requiresIssuer: Bool
    let registration: URL?
    let supportsRefresh: Bool

    init(_ json: OpenAIJSON, configuration: OpenAIMCPOAuthConfiguration) throws {
        guard json["issuer"].string == configuration.issuer,
              json["code_challenge_methods_supported"].array?.contains("S256") == true,
              json["token_endpoint_auth_methods_supported"].array?.contains("none") == true,
              let authorization = json["authorization_endpoint"].string,
              let token = json["token_endpoint"].string else { throw OpenAIMCPOAuthFailure.metadata }
        issuer = configuration.issuer
        self.authorization = try OpenAIMCPOAuthConfiguration.https(authorization)
        self.token = try OpenAIMCPOAuthConfiguration.https(token)
        requiresIssuer = json["authorization_response_iss_parameter_supported"] == true
        registration = try json["registration_endpoint"].string.map(OpenAIMCPOAuthConfiguration.https)
        if json["grant_types_supported"] != .null {
            guard let grants = json["grant_types_supported"].array, grants.contains("authorization_code") else { throw OpenAIMCPOAuthFailure.metadata }
            supportsRefresh = grants.contains("refresh_token")
        } else {
            supportsRefresh = true
        }
    }
}

nonisolated struct OpenAIMCPOAuthAttempt: Sendable {
    let configuration: OpenAIMCPOAuthConfiguration
    let metadata: OpenAIMCPOAuthMetadata
    let state: String
    let verifier: String

    init(configuration: OpenAIMCPOAuthConfiguration, metadata: OpenAIMCPOAuthMetadata) throws {
        self.configuration = configuration
        self.metadata = metadata
        state = try Self.random()
        verifier = try Self.random()
    }

    static func challenge(_ verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw OpenAIMCPOAuthFailure.unavailable }
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    func authorizationURL() throws -> URL {
        var url = try URLComponents(url: metadata.authorization, resolvingAgainstBaseURL: false).unwrap()
        var fields = ["response_type": "code", "client_id": configuration.clientID,
                      "redirect_uri": OpenAIMCPOAuthConfiguration.redirect, "state": state,
                      "code_challenge": Self.challenge(verifier), "code_challenge_method": "S256",
        ]
        if !configuration.scope.isEmpty { fields["scope"] = configuration.scope }
        if !configuration.resource.isEmpty { fields["resource"] = configuration.resource }
        url.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return try url.url.unwrap()
    }

    func exchangeFields(callback: URL) throws -> [String: String] {
        guard let url = URLComponents(url: callback, resolvingAgainstBaseURL: false), url.fragment == nil,
              url.scheme == "com.kavoye.linen.oauth", url.host == "callback", url.path.isEmpty,
              url.user == nil, url.password == nil, url.port == nil else { throw OpenAIMCPOAuthFailure.callback }
        let items = url.queryItems ?? []
        guard Set(items.map(\.name)).count == items.count else { throw OpenAIMCPOAuthFailure.callback }
        let fields = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        guard fields["state"] == state,
              (!metadata.requiresIssuer && fields["iss"] == nil) || fields["iss"] == metadata.issuer
        else { throw OpenAIMCPOAuthFailure.callback }
        guard fields["error"] == nil else { throw OpenAIMCPOAuthFailure.cancelled }
        guard let code = fields["code"], !code.isEmpty, code.utf8.count <= 16_384,
              fields["access_token"] == nil else { throw OpenAIMCPOAuthFailure.callback }
        var result = ["grant_type": "authorization_code", "code": code, "code_verifier": verifier,
                      "client_id": configuration.clientID, "redirect_uri": OpenAIMCPOAuthConfiguration.redirect,
        ]
        if !configuration.resource.isEmpty { result["resource"] = configuration.resource }
        return result
    }

    static func form(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let text = fields.sorted { $0.key < $1.key }.map {
            ($0.key.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") + "=" + ($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        }.joined(separator: "&")
        return Data(text.utf8)
    }
}

nonisolated struct OpenAIMCPOAuthCredential: Codable, Equatable, Sendable {
    var sessionID = UUID()
    let binding: String
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    let tokenEndpoint: URL

    init(response: OpenAIJSON, binding: String, endpoint: URL, previous: Self? = nil, now: Date = Date()) throws {
        guard response["token_type"].string?.lowercased() == "bearer",
              let access = response["access_token"].string, Self.validToken(access) else { throw OpenAIMCPOAuthFailure.token }
        accessToken = access
        self.binding = binding
        tokenEndpoint = endpoint
        if let previous {
            sessionID = previous.sessionID
        }
        guard response["refresh_token"] == .null || response["refresh_token"].string != nil else { throw OpenAIMCPOAuthFailure.token }
        refreshToken = response["refresh_token"].string ?? previous?.refreshToken
        if let refreshToken, !Self.validToken(refreshToken) {
            throw OpenAIMCPOAuthFailure.token
        }
        if response["expires_in"] != .null {
            guard let seconds = OpenAIComputerCall.number(response["expires_in"]), seconds > 0, seconds <= 315_576_000 else { throw OpenAIMCPOAuthFailure.token }
            expiresAt = now.addingTimeInterval(seconds)
        }
    }

    private static func validToken(_ token: String) -> Bool {
        !token.isEmpty && token.utf8.count <= 65_536 && token.unicodeScalars.allSatisfy { (33...126).contains($0.value) }
    }
}

nonisolated enum OpenAIMCPOAuthFailure: LocalizedError, Equatable {
    case configuration, metadata, callback, token, unavailable, cancelled, signIn, storage, discovery, registration, registrationUnavailable
    var errorDescription: String? {
        switch self {
        case .configuration:
            String(localized: "Enter an HTTPS OAuth issuer, a public client ID, and the requested scopes.")
        case .metadata:
            String(localized: "This issuer does not advertise a matching public client OAuth flow with PKCE S256.")
        case .callback:
            String(localized: "The sign-in response could not be verified. Try signing in again.")
        case .token:
            String(localized: "The authorization server returned an invalid token response.")
        case .unavailable:
            String(localized: "The authorization server could not be reached. Try again.")
        case .cancelled:
            String(localized: "Sign-in was canceled.")
        case .signIn:
            String(localized: "Sign in to this MCP connection in OpenAI settings.")
        case .storage:
            String(localized: "The Keychain could not update this MCP sign-in.")
        case .discovery:
            String(localized: "This server did not provide valid OAuth discovery information. Enter the connection details manually.")
        case .registration:
            String(localized: "The authorization server did not register the requested public client. Enter a registered client ID manually.")
        case .registrationUnavailable:
            String(localized: "This issuer does not offer dynamic client registration. Enter a registered client ID.")
        }
    }
}

private nonisolated extension Optional {
    func unwrap() throws -> Wrapped {
        guard let value = self else { throw OpenAIMCPOAuthFailure.configuration }
        return value
    }
}
