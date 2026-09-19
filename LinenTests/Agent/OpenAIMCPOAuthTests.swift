// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import Security
import Synchronization
import Testing

@testable import Linen

@MainActor
@Suite(.serialized)
struct OpenAIMCPOAuthTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var configuration: OpenAIMCPOAuthConfiguration {
        .init(issuer: "https://identity.example.test/tenant", clientID: "linen-client", scope: "files:read offline_access", resource: "https://mcp.example.test")
    }
    private var server: OpenAIMCPServer {
        .init(label: "fixture", destination: "https://mcp.example.test/mcp", requiresAuthorization: true, oauth: configuration)
    }
    private var metadata: OpenAIJSON {
        ["issuer": .string(configuration.issuer), "authorization_endpoint": "https://identity.example.test/authorize", "token_endpoint": "https://identity.example.test/token",
         "code_challenge_methods_supported": ["S256"], "token_endpoint_auth_methods_supported": ["none"], "authorization_response_iss_parameter_supported": true,
        ]
    }
    private var tokens: OpenAIJSON {
        ["access_token": "fixture-access", "refresh_token": "fixture-refresh", "token_type": "Bearer", "expires_in": 3600]
    }
    private func callback(_ authorization: URL, changes: [String: String] = [:]) throws -> URL {
        let query = try #require(URLComponents(url: authorization, resolvingAgainstBaseURL: false)?.queryItems)
        var fields = ["state": try #require(query.first { $0.name == "state" }?.value), "code": "code +&=%/", "iss": configuration.issuer]
        fields.merge(changes) { _, new in new }
        var url = try #require(URLComponents(string: OpenAIMCPOAuthConfiguration.redirect))
        url.queryItems = fields.map { .init(name: $0.key, value: $0.value) }
        return try #require(url.url)
    }
    private func credential(_ server: OpenAIMCPServer, expired: Bool = false) throws -> OpenAIMCPOAuthCredential {
        var result = try OpenAIMCPOAuthCredential(response: tokens, binding: configuration.binding(destination: server.destination),
                                                endpoint: URL(string: "https://identity.example.test/token")!, now: now)
        if expired {
            result.expiresAt = now.addingTimeInterval(-1)
        }
        return result
    }

    @Test func pkceMatchesThePublishedS256VectorAndChangesForEveryAttempt() throws {
        #expect(OpenAIMCPOAuthAttempt.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let discovery = try OpenAIMCPOAuthMetadata(metadata, configuration: configuration)
        let first = try OpenAIMCPOAuthAttempt(configuration: configuration, metadata: discovery)
        let second = try OpenAIMCPOAuthAttempt(configuration: configuration, metadata: discovery)
        #expect(first.state != second.state && first.verifier != second.verifier)
        #expect(first.verifier.count == 43 && first.state.count == 43)
        let url = try first.authorizationURL()
        #expect(!url.absoluteString.contains(first.verifier))
        let fields = try first.exchangeFields(callback: callback(url))
        #expect(fields["code_verifier"] == first.verifier && fields["resource"] == configuration.resource)
        #expect(fields["redirect_uri"] == OpenAIMCPOAuthConfiguration.redirect)
        #expect(String(decoding: OpenAIMCPOAuthAttempt.form(fields), as: UTF8.self).contains("code=code%20%2B%26%3D%25%2F"))
    }

    @Test func callbackRejectsWrongStateIssuerDuplicateFieldsAndImplicitTokens() throws {
        let attempt = try OpenAIMCPOAuthAttempt(configuration: configuration, metadata: .init(metadata, configuration: configuration))
        let url = try attempt.authorizationURL()
        for changes in [["state": "wrong"], ["iss": "https://other.example.test"], ["error": "access_denied"], ["access_token": "secret"]] {
            #expect(throws: OpenAIMCPOAuthFailure.self) { try attempt.exchangeFields(callback: callback(url, changes: changes)) }
        }
        let correct = try callback(url).absoluteString
        for invalid in [correct + "&state=duplicate", correct + "#secret", correct.replacingOccurrences(of: "://callback?", with: "://callback/other?") ] {
            #expect(throws: OpenAIMCPOAuthFailure.self) { try attempt.exchangeFields(callback: URL(string: invalid)!) }
        }
        var missing = try #require(URLComponents(url: callback(url), resolvingAgainstBaseURL: false))
        missing.queryItems?.removeAll { $0.name == "iss" }
        #expect(throws: OpenAIMCPOAuthFailure.self) { try attempt.exchangeFields(callback: missing.url!) }
    }

    @Test func discoveryRejectsInsecureMismatchedAndNonPKCEIssuers() throws {
        #expect(try configuration.metadataURLs().map(\.absoluteString) == [
            "https://identity.example.test/.well-known/oauth-authorization-server/tenant",
            "https://identity.example.test/.well-known/openid-configuration/tenant",
            "https://identity.example.test/tenant/.well-known/openid-configuration",
        ])
        for endpoint in ["http://identity.example.test", "https://user:pass@identity.example.test", "https://identity.example.test?query=1", "https://identity.example.test#fragment"] {
            var config = configuration; config.issuer = endpoint
            #expect(throws: OpenAIMCPOAuthFailure.self) { try config.validate() }
        }
        for (key, value): (String, OpenAIJSON) in [("issuer", "https://other.example.test"), ("code_challenge_methods_supported", ["plain"]),
                                                  ("token_endpoint_auth_methods_supported", ["client_secret_basic"]), ("token_endpoint", "http://identity.example.test/token"),
        ] {
            var invalid = metadata; invalid[key] = value
            #expect(throws: OpenAIMCPOAuthFailure.self) { try OpenAIMCPOAuthMetadata(invalid, configuration: configuration) }
        }
    }

    @Test func signInDiscoversOIDCFallbackAndCommitsOnlyWhenRequested() async throws {
        let transport = OAuthTransportFixture([.init(status: 404, data: Data()), try .json(metadata), try .json(tokens)])
        let store = OAuthMemoryStorage()
        let manager = OpenAIMCPOAuthManager(transport: transport, storage: store, now: { now })
        let server = server
        let credential = try await manager.authorize(server: server) { try callback($0) }
        #expect(store.value == nil)
        try manager.commit(credential, server: server, providerID: "fixture")
        #expect(store.value?.refreshToken == "fixture-refresh")
        let requests = await transport.requests
        #expect(requests.count == 3)
        #expect(requests[1].url?.path == "/.well-known/openid-configuration/tenant")
        #expect(requests[2].httpMethod == "POST")
        #expect(requests[2].value(forHTTPHeaderField: "Authorization") == nil)
        #expect(requests[2].value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
    }

    @Test func concurrentRequestsRefreshOnceAndPersistRotatedCredentials() async throws {
        let gate = ResponseGate()
        var updated = tokens; updated["access_token"] = "rotated-access"; updated["refresh_token"] = "rotated-refresh"
        let transport = OAuthTransportFixture([try .json(updated)], gate: gate)
        let store = OAuthMemoryStorage()
        var server = server
        let original = try credential(server, expired: true)
        store.value = original; server.authorizationRevision = original.sessionID
        let manager = OpenAIMCPOAuthManager(transport: transport, storage: store, now: { now })
        let first = Task { try await manager.accessToken(server: server, providerID: "fixture") }
        let second = Task { try await manager.accessToken(server: server, providerID: "fixture") }
        #expect(await waitUntil { gate.requestCount == 1 })
        gate.open()
        #expect(try await first.value == "rotated-access")
        #expect(try await second.value == "rotated-access")
        #expect(await transport.requests.count == 1)
        #expect(store.value?.refreshToken == "rotated-refresh")
        #expect(store.value?.sessionID == original.sessionID)
        #expect(try await manager.accessToken(server: server, providerID: "fixture") == "rotated-access")
        #expect(await transport.requests.count == 1)
    }

    @Test func disconnectAndNewLoginCannotBeUndoneByAnOlderRefresh() async throws {
        for replace in [false, true] {
            let gate = ResponseGate()
            let transport = OAuthTransportFixture([try .json(tokens)], gate: gate)
            let store = OAuthMemoryStorage()
            var server = server
            let original = try credential(server, expired: true)
            store.value = original; server.authorizationRevision = original.sessionID
            let manager = OpenAIMCPOAuthManager(transport: transport, storage: store, now: { now })
            let request = Task { try await manager.accessToken(server: server, providerID: "fixture") }
            #expect(await waitUntil { gate.requestCount == 1 })
            let new = try credential(server)
            if replace { try manager.commit(new, server: server, providerID: "fixture") } else { try manager.disconnect(serverID: server.id, providerID: "fixture") }
            gate.open()
            await #expect(throws: (any Error).self) { try await request.value }
            #expect(store.value == (replace ? new : nil))
        }
    }

    @Test func wrongDestinationOrLoginRevisionNeverUsesAToken() async throws {
        let transport = OAuthTransportFixture([])
        let store = OAuthMemoryStorage()
        var server = server
        store.value = try credential(server)
        let manager = OpenAIMCPOAuthManager(transport: transport, storage: store, now: { now })
        await #expect(throws: OpenAIMCPOAuthFailure.self) { try await manager.accessToken(server: server, providerID: "fixture") }
        server.authorizationRevision = store.value?.sessionID
        server.destination = "https://other.example.test/mcp"
        await #expect(throws: OpenAIMCPOAuthFailure.self) { try await manager.accessToken(server: server, providerID: "fixture") }
        #expect(await transport.requests.isEmpty)
    }

    @Test func refreshFailureDoesNotSendAResponseRequestOrOverwriteCredentials() async throws {
        let transport = OAuthTransportFixture([try .json(["error": "invalid_grant", "error_description": "fixture-secret"], status: 400)])
        let store = OAuthMemoryStorage()
        var server = server
        let original = try credential(server, expired: true)
        store.value = original; server.authorizationRevision = original.sessionID
        let manager = OpenAIMCPOAuthManager(transport: transport, storage: store, now: { now })
        let wire = OpenAITransportFixture([])
        var settings = OpenAIResponseSettings(); settings.mcpServers = [server]
        let client = OpenAIResponsesClient(endpoint: URL(string: "https://api.example.test/v1")!, apiKey: "fixture", model: "fixture", settings: settings,
                                           transport: wire, oauthAuthorization: { server, providerID in try await manager.accessToken(server: server, providerID: providerID) })
        await #expect(throws: OpenAIMCPOAuthFailure.signIn) {
            try await client.respond(transcript: .init(entries: []), prompt: "Inspect", images: [], state: client.restoring(nil), tools: [], maxTokens: 100, onText: { _ in })
        }
        #expect(store.value == original)
        #expect(wire.requests.isEmpty)
        #expect(!OpenAIMCPOAuthFailure.signIn.localizedDescription.contains("fixture-secret"))
    }

    @Test func tokenRotationPreservesRefreshWhenOmittedAndRejectsMalformedResponses() throws {
        let original = try credential(server)
        var response = tokens; response["refresh_token"] = .null
        let updated = try OpenAIMCPOAuthCredential(response: response, binding: original.binding, endpoint: original.tokenEndpoint, previous: original, now: now)
        #expect(updated.refreshToken == original.refreshToken)
        for (key, value): (String, OpenAIJSON) in [("access_token", ""), ("access_token", "token\nsecret"), ("token_type", "MAC"),
                                                  ("expires_in", -1), ("expires_in", "3600"), ("refresh_token", 42),
        ] {
            var invalid = tokens; invalid[key] = value
            #expect(throws: OpenAIMCPOAuthFailure.self) {
                try OpenAIMCPOAuthCredential(response: invalid, binding: original.binding, endpoint: original.tokenEndpoint, now: now)
            }
        }
    }

    @Test func cancelledOrInvalidSignInNeverExchangesOrStoresCredentials() async throws {
        for cancelled in [false, true] {
            let transport = OAuthTransportFixture([try .json(metadata)])
            let store = OAuthMemoryStorage()
            let manager = OpenAIMCPOAuthManager(transport: transport, storage: store)
            await #expect(throws: (any Error).self) {
                try await manager.authorize(server: server) { url in
                    if cancelled {
                        throw CancellationError()
                    }
                    return try callback(url, changes: ["state": "wrong"])
                }
            }
            #expect(store.value == nil)
            #expect(await transport.requests.count == 1)
        }
    }

    @Test func responsesResolveOAuthOnEveryRequestWithoutPersistingSecrets() async throws {
        let wire = OpenAITransportFixture([OpenAITransportFixture.response([OpenAITransportFixture.message("Done")]),
                                           OpenAITransportFixture.response([OpenAITransportFixture.message("Done again")]),
        ])
        let transport = OAuthTransportFixture([try .json(tokens)])
        let store = OAuthMemoryStorage()
        var server = server
        let original = try credential(server, expired: true)
        store.value = original; server.authorizationRevision = original.sessionID
        let manager = OpenAIMCPOAuthManager(transport: transport, storage: store, now: { now })
        var settings = OpenAIResponseSettings(); settings.mcpServers = [server]
        let client = OpenAIResponsesClient(endpoint: URL(string: "https://api.example.test/v1")!, apiKey: "fixture", model: "fixture", settings: settings,
                                           transport: wire, oauthAuthorization: { server, providerID in try await manager.accessToken(server: server, providerID: providerID) })
        for prompt in ["Inspect", "Inspect again"] {
            let step = try await client.respond(transcript: .init(entries: []), prompt: prompt, images: [], state: client.restoring(nil), tools: [], maxTokens: 100, onText: { _ in })
            let saved = try OpenAIJSON.encode(step.state).text()
            #expect(!saved.contains("fixture-access") && !saved.contains("fixture-refresh"))
        }
        #expect(wire.requests.count == 2)
        #expect(await transport.requests.count == 1)
        for request in wire.requests {
            let body = try OpenAIJSON.decode(try #require(request.body))
            #expect(body["tools"].array?.first?["authorization"] == "fixture-access")
            #expect(body["tools"].array?.first?["require_approval"] == "always")
        }
        #expect(try !OpenAIJSON.encode(settings).text().contains("fixture-access"))
        settings.mcpServers[0].authorizationRevision = UUID()
        let relinked = OpenAIResponsesClient(endpoint: URL(string: "https://api.example.test/v1")!, apiKey: "fixture", model: "fixture", settings: settings)
        #expect(relinked.binding != client.binding)
    }

    @Test(arguments: [302, 307, 308])
    func tokenTransportDoesNotFollowRedirects(_ status: Int) async throws {
        let trap = ResponseGate(); trap.open()
        let destination = try await HTTPFixtureServer.start(routes: ["/token": .html("Unexpected", gate: trap)])
        let redirect = try HTTPFixtureServer.Response(status: "\(status) Redirect", headers: ["Location": destination.url("/token").absoluteString], body: Data())
        let origin = try await HTTPFixtureServer.start(routes: ["/token": redirect])
        var request = try URLRequest(url: origin.url("/token")); request.httpMethod = "POST"
        request.httpBody = Data("refresh_token=fixture-secret".utf8)
        let result = try await OpenAIMCPOAuthHTTP().send(request)
        #expect(result.status == status)
        #expect(trap.requestCount == 0)
    }

    @Test func credentialRoundTripKeepsOAuthSeparateFromManualTokens() throws {
        let values = Mutex<[String: String]>([:])
        let storage = CredentialStore.Storage(
            read: { account in values.withLock { $0[account] } },
            write: { value, account in
                values.withLock { $0[account] = value }
                return errSecSuccess
            },
            delete: { account in
                values.withLock { $0.removeValue(forKey: account) == nil ? errSecItemNotFound : errSecSuccess }
            }
        )
        let server = server
        let providerID = "fixture"
        let credential = try credential(server)
        #expect(CredentialStore.saveMCPAuthorization("manual-token", providerID: providerID, serverID: server.id, storage: storage) == nil)
        try CredentialStore.saveMCPOAuth(credential, providerID: providerID, serverID: server.id, storage: storage)
        #expect(CredentialStore.mcpOAuth(providerID: providerID, serverID: server.id, storage: storage) == credential)
        #expect(CredentialStore.mcpAuthorization(providerID: providerID, serverID: server.id, storage: storage) == "manual-token")
        #expect(CredentialStore.mcpOAuth(providerID: "another-provider", serverID: server.id, storage: storage) == nil)
        #expect(CredentialStore.mcpOAuth(providerID: providerID, serverID: UUID(), storage: storage) == nil)
        try CredentialStore.saveMCPOAuth(nil, providerID: providerID, serverID: server.id, storage: storage)
        #expect(CredentialStore.mcpOAuth(providerID: providerID, serverID: server.id, storage: storage) == nil)
        #expect(CredentialStore.mcpAuthorization(providerID: providerID, serverID: server.id, storage: storage) == "manual-token")
        try CredentialStore.saveMCPOAuth(nil, providerID: providerID, serverID: server.id, storage: storage)
    }

    @Test func credentialStorageReportsWriteAndDeleteFailures() throws {
        let storage = CredentialStore.Storage(
            read: { _ in nil },
            write: { _, _ in errSecMissingEntitlement },
            delete: { _ in errSecMissingEntitlement }
        )
        let server = server
        let credential = try credential(server)
        #expect(throws: OpenAIMCPOAuthFailure.storage) {
            try CredentialStore.saveMCPOAuth(credential, providerID: "fixture", serverID: server.id, storage: storage)
        }
        #expect(throws: OpenAIMCPOAuthFailure.storage) {
            try CredentialStore.saveMCPOAuth(nil, providerID: "fixture", serverID: server.id, storage: storage)
        }
    }

    @Test func failedRotationStorageNeverReturnsAnUnpersistedAccessToken() async throws {
        let transport = OAuthTransportFixture([try .json(tokens)])
        let store = OAuthMemoryStorage()
        var server = server
        let original = try credential(server, expired: true)
        store.value = original; store.rejectWrites = true; server.authorizationRevision = original.sessionID
        let manager = OpenAIMCPOAuthManager(transport: transport, storage: store, now: { now })
        await #expect(throws: OpenAIMCPOAuthFailure.storage) { try await manager.accessToken(server: server, providerID: "fixture") }
        #expect(store.value == original)
    }
}

@MainActor
private final class OAuthMemoryStorage: OpenAIMCPOAuthStorage {
    var value: OpenAIMCPOAuthCredential?
    var rejectWrites = false
    func load(providerID: String, serverID: UUID) -> OpenAIMCPOAuthCredential? {
        value
    }
    func save(_ credential: OpenAIMCPOAuthCredential?, providerID: String, serverID: UUID) throws {
        if rejectWrites {
            throw OpenAIMCPOAuthFailure.storage
        }
        value = credential
    }
}

private actor OAuthTransportFixture: OpenAIMCPOAuthTransport {
    var responses: [OpenAIMCPOAuthHTTPResult]
    var requests: [URLRequest] = []
    let gate: ResponseGate?
    init(_ responses: [OpenAIMCPOAuthHTTPResult], gate: ResponseGate? = nil) { self.responses = responses; self.gate = gate }
    func send(_ request: URLRequest) async throws -> OpenAIMCPOAuthHTTPResult {
        requests.append(request)
        guard !responses.isEmpty else { throw OpenAIMCPOAuthFailure.unavailable }
        let response = responses.removeFirst()
        if let gate {
            await withCheckedContinuation { continuation in gate.submit { continuation.resume() } }
        }
        return response
    }
}

private nonisolated extension OpenAIMCPOAuthHTTPResult {
    static func json(_ json: OpenAIJSON, status: Int = 200) throws -> Self { .init(status: status, data: try json.data()) }
}
