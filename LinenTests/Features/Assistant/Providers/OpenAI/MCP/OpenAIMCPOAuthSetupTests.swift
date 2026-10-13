// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@MainActor
struct OpenAIMCPOAuthSetupTests {
    static let endpoint = "https://mcp.example.test/mcp"
    static let issuer = "https://identity.example.test"
    static let resource: OpenAIJSON = ["resource": .string(endpoint), "authorization_servers": [.string(issuer)], "scopes_supported": ["files:read"]]
    static let metadata: OpenAIJSON = ["issuer": .string(issuer), "authorization_endpoint": .string(issuer + "/authorize"),
                                      "token_endpoint": .string(issuer + "/token"), "registration_endpoint": .string(issuer + "/register"),
                                      "code_challenge_methods_supported": ["S256"], "token_endpoint_auth_methods_supported": ["none"],
    ]
    static let registration: OpenAIJSON = ["client_id": "registered-fixture", "redirect_uris": [.string(OpenAIMCPOAuthConfiguration.redirect)],
                                          "token_endpoint_auth_method": "none", "grant_types": ["authorization_code", "refresh_token"], "response_types": ["code"],
    ]

    @Test func challengeHandlesSchemesEscapesCommasAndCase() throws {
        let challenge = try OpenAIMCPOAuthChallenge(#"Basic realm="ignored, Bearer", bEaReR realm="a\"b,c", RESOURCE_METADATA="https://mcp.example.test/metadata?x=a,b", scope="files:read more:read", Digest realm="other""#)
        #expect(challenge.parameters["realm"] == "a\"b,c")
        #expect(challenge.parameters["resource_metadata"] == "https://mcp.example.test/metadata?x=a,b")
        #expect(challenge.parameters["scope"] == "files:read more:read")
        #expect(try OpenAIMCPOAuthChallenge("Bearer scope = read").parameters["scope"] == "read")
    }

    @Test(arguments: [#"Bearer scope="a", scope="b""#, #"Bearer scope="a", Bearer scope="b""#, #"Bearer scope="unfinished"#, "Bearer scope=a\r\nx: bad", #"Bearer resource_metadata="https://a.test"suffix"#])
    func ambiguousChallengesAreRejected(_ header: String) {
        #expect(throws: OpenAIMCPOAuthFailure.self) { try OpenAIMCPOAuthChallenge(header) }
    }

    @Test func challengeLocationAndScopesTakePrecedence() async throws {
        let transport = OAuthSetupFixture([
            .init(status: 401, data: Data(), headers: ["WWW-Authenticate": "Bearer resource_metadata=\"https://discovery.example.test/resource\", scope=\"other:read\""]),
            try .setupJSON(Self.resource),
        ])
        let result = try await OpenAIMCPOAuthSetup(transport: transport).discover(destination: Self.endpoint)
        #expect(result == .init(resource: Self.endpoint, issuers: [Self.issuer], scope: "other:read"))
        let requests = await transport.requests
        #expect(requests.map { $0.url?.absoluteString } == [Self.endpoint, "https://discovery.example.test/resource"])
        #expect(requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil && $0.value(forHTTPHeaderField: "Authorization") == nil })
    }

    @Test func wellKnownFallbackBindsRootMetadataToRootResource() async throws {
        var root = Self.resource; root["resource"] = "https://mcp.example.test"
        let transport = OAuthSetupFixture([.init(status: 405, data: Data()), .init(status: 404, data: Data()), try .setupJSON(root)])
        let result = try await OpenAIMCPOAuthSetup(transport: transport).discover(destination: Self.endpoint)
        #expect(result.resource == "https://mcp.example.test")
        #expect(result.scope == "files:read")
        #expect(await transport.requests.map { $0.url?.path } == ["/mcp", "/.well-known/oauth-protected-resource/mcp", "/.well-known/oauth-protected-resource"])
    }

    @Test func invalidMetadataNeverFallsThroughToAnotherResource() async throws {
        for (key, value): (String, OpenAIJSON) in [("resource", "https://other.example.test"), ("authorization_servers", ["http://identity.example.test"]),
                                                  ("authorization_servers", []), ("scopes_supported", ["read write"]), ("scopes_supported", [3]),
        ] {
            var invalid = Self.resource; invalid[key] = value
            let transport = OAuthSetupFixture([.init(status: 401, data: Data()), try .setupJSON(invalid)])
            await #expect(throws: OpenAIMCPOAuthFailure.self) { try await OpenAIMCPOAuthSetup(transport: transport).discover(destination: Self.endpoint) }
            #expect(await transport.requests.count == 2)
        }
    }

    @Test func challengeResourceMustMatchOriginalEndpointEvenForExternalMetadata() async throws {
        var invalid = Self.resource; invalid["resource"] = "https://mcp.example.test"
        let transport = OAuthSetupFixture([.init(status: 401, data: Data(), headers: ["www-authenticate": "Bearer resource_metadata=\"https://mcp.example.test/meta\""]), try .setupJSON(invalid)])
        await #expect(throws: OpenAIMCPOAuthFailure.self) { try await OpenAIMCPOAuthSetup(transport: transport).discover(destination: Self.endpoint) }
    }

    @Test func anonymousProbeDoesNotTrustAnUnrelatedAuthenticationHeader() async throws {
        var multiple = Self.resource
        multiple["authorization_servers"] = [.string(Self.issuer), "https://other.example.test", .string(Self.issuer)]
        multiple["scopes_supported"] = .null
        let transport = OAuthSetupFixture([.init(status: 200, data: Data(), headers: ["www-authenticate": "Bearer resource_metadata=\"https://wrong.example.test\""]), try .setupJSON(multiple)])
        let result = try await OpenAIMCPOAuthSetup(transport: transport).discover(destination: Self.endpoint)
        #expect(result.issuers == [Self.issuer, "https://other.example.test"])
        #expect(result.scope.isEmpty)
        #expect(await transport.requests.last?.url?.path == "/.well-known/oauth-protected-resource/mcp")
    }

    @Test(arguments: [302, 403, 429, 500])
    func unsuccessfulProbeStopsDiscovery(_ status: Int) async {
        let transport = OAuthSetupFixture([.init(status: status, data: Data())])
        await #expect(throws: OpenAIMCPOAuthFailure.self) { try await OpenAIMCPOAuthSetup(transport: transport).discover(destination: Self.endpoint) }
        #expect(await transport.requests.count == 1)
    }

    @Test func registrationCreatesOnlyTheRequestedPublicClient() async throws {
        let transport = OAuthSetupFixture([try .setupJSON(Self.metadata), try .setupJSON(Self.registration, status: 201)])
        let client = try await OpenAIMCPOAuthSetup(transport: transport).register(issuer: Self.issuer, scope: "files:read", resource: Self.endpoint)
        #expect(client == "registered-fixture")
        let requests = await transport.requests
        #expect(requests.count == 2)
        let request = try #require(requests.last)
        #expect(request.url?.absoluteString == Self.issuer + "/register")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let body = try OpenAIJSON.decode(#require(request.httpBody))
        #expect(body["token_endpoint_auth_method"] == "none")
        #expect(body["application_type"] == "native")
        #expect(body["scope"] == "files:read")
        #expect(body["redirect_uris"] == Self.registration["redirect_uris"])
    }

    @Test func registrationRejectsSecretsRedirectChangesAndUnexpectedGrantsWithoutRetry() async throws {
        for (key, value): (String, OpenAIJSON) in [("client_secret", "fixture-secret"), ("token_endpoint_auth_method", "client_secret_post"),
                                                  ("redirect_uris", ["https://other.example.test/callback"]), ("grant_types", ["client_credentials"]),
                                                  ("client_id", ""), ("response_types", ["token"]),
        ] {
            var invalid = Self.registration; invalid[key] = value
            let transport = OAuthSetupFixture([try .setupJSON(Self.metadata), try .setupJSON(invalid, status: 201)])
            await #expect(throws: OpenAIMCPOAuthFailure.self) { try await OpenAIMCPOAuthSetup(transport: transport).register(issuer: Self.issuer, scope: "", resource: Self.endpoint) }
            #expect(await transport.requests.count == 2)
        }
    }

    @Test func missingRegistrationEndpointDoesNotCreateAClient() async throws {
        var metadata = Self.metadata; metadata["registration_endpoint"] = .null
        let transport = OAuthSetupFixture([try .setupJSON(metadata)])
        await #expect(throws: OpenAIMCPOAuthFailure.registrationUnavailable) { try await OpenAIMCPOAuthSetup(transport: transport).register(issuer: Self.issuer, scope: "", resource: Self.endpoint) }
        #expect(await transport.requests.count == 1)
    }

    @Test func cancellingDiscoveryPreventsRegistrationPOST() async throws {
        let gate = ResponseGate()
        let transport = OAuthSetupFixture([try .setupJSON(Self.metadata)], gate: gate)
        let task = Task { try await OpenAIMCPOAuthSetup(transport: transport).register(issuer: Self.issuer, scope: "", resource: Self.endpoint) }
        try #require(await waitUntil { gate.requestCount == 1 })
        task.cancel()
        gate.open()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await transport.requests.count == 1)
    }

    @Test func registrationRespectsAnIssuerWithoutRefreshGrants() async throws {
        var metadata = Self.metadata; metadata["grant_types_supported"] = ["authorization_code"]
        var registration = Self.registration; registration["grant_types"] = ["authorization_code"]
        let transport = OAuthSetupFixture([try .setupJSON(metadata), try .setupJSON(registration, status: 201)])
        _ = try await OpenAIMCPOAuthSetup(transport: transport).register(issuer: Self.issuer, scope: "", resource: Self.endpoint)
        let request = try #require(await transport.requests.last)
        let body = try OpenAIJSON.decode(#require(request.httpBody))
        #expect(body["grant_types"] == ["authorization_code"])
    }

    @Test func issuerFallbackPreservesTenantPathsAndIncludesBothOIDCForms() async throws {
        var metadata = Self.metadata; metadata["issuer"] = .string(Self.issuer + "/tenant/")
        let transport = OAuthSetupFixture([.init(status: 404, data: Data()), .init(status: 410, data: Data()), try .setupJSON(metadata), try .setupJSON(Self.registration, status: 201)])
        _ = try await OpenAIMCPOAuthSetup(transport: transport).register(issuer: Self.issuer + "/tenant/", scope: "", resource: Self.endpoint)
        #expect(await transport.requests.prefix(3).map { $0.url?.absoluteString } == [
            Self.issuer + "/.well-known/oauth-authorization-server/tenant/",
            Self.issuer + "/.well-known/openid-configuration/tenant/",
            Self.issuer + "/tenant/.well-known/openid-configuration",
        ])
    }

    @Test func realHTTPProbeReturnsHeadersWithoutConsumingTheBody() async throws {
        let responseBody = HTTPFixtureServer.Response(status: "401 Unauthorized", headers: ["WWW-Authenticate": "Bearer scope=read"], body: Data(repeating: 65, count: 1_100_000))
        let site = try await HTTPFixtureServer.start(routes: ["/probe": responseBody])
        let response = try await OpenAIMCPOAuthHTTP().probe(URLRequest(url: site.url("/probe")))
        #expect(response.status == 401)
        #expect(response.data.isEmpty)
        #expect(response.headers["www-authenticate"] == "Bearer scope=read")
    }
}

actor OAuthSetupFixture: OpenAIMCPOAuthTransport {
    private var responses: [OpenAIMCPOAuthHTTPResult]
    private let gate: ResponseGate?
    private(set) var requests: [URLRequest] = []
    init(_ responses: [OpenAIMCPOAuthHTTPResult], gate: ResponseGate? = nil) { self.responses = responses; self.gate = gate }
    func send(_ request: URLRequest) async throws -> OpenAIMCPOAuthHTTPResult {
        requests.append(request)
        if let gate {
            await withCheckedContinuation { continuation in gate.submit { continuation.resume() } }
        }
        guard !responses.isEmpty else { throw OpenAIMCPOAuthFailure.unavailable }
        return responses.removeFirst()
    }
}

nonisolated extension OpenAIMCPOAuthHTTPResult {
    static func setupJSON(_ json: OpenAIJSON, status: Int = 200) throws -> Self { .init(status: status, data: try json.data()) }
}
