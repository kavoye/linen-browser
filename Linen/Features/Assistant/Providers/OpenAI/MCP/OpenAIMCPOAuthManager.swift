// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct OpenAIMCPOAuthHTTPResult: Sendable {
    let status: Int
    let data: Data
    var headers: [String: String] = [:]
}

nonisolated protocol OpenAIMCPOAuthTransport: Sendable {
    func send(_ request: URLRequest) async throws -> OpenAIMCPOAuthHTTPResult
    func probe(_ request: URLRequest) async throws -> OpenAIMCPOAuthHTTPResult
}

nonisolated extension OpenAIMCPOAuthTransport {
    func probe(_ request: URLRequest) async throws -> OpenAIMCPOAuthHTTPResult {
        try await send(request)
    }
}

nonisolated struct OpenAIMCPOAuthHTTP: OpenAIMCPOAuthTransport {
    func send(_ request: URLRequest) async throws -> OpenAIMCPOAuthHTTPResult {
        try await send(request, headersOnly: false)
    }

    func probe(_ request: URLRequest) async throws -> OpenAIMCPOAuthHTTPResult {
        try await send(request, headersOnly: true)
    }

    private func send(_ request: URLRequest, headersOnly: Bool) async throws -> OpenAIMCPOAuthHTTPResult {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration, delegate: OAuthNoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse, response.url == request.url else { throw OpenAIMCPOAuthFailure.unavailable }
            let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, field in
                if let key = field.key as? String, let value = field.value as? String {
                    result[key.lowercased()] = value
                }
            }
            if headersOnly {
                return .init(status: response.statusCode, data: Data(), headers: headers)
            }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 1_048_576 else { throw OpenAIMCPOAuthFailure.unavailable }
                data.append(byte)
            }
            return .init(status: response.statusCode, data: data, headers: headers)
        } catch is CancellationError { throw CancellationError() } catch { throw OpenAIMCPOAuthFailure.unavailable }
    }
}

private nonisolated final class OAuthNoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
protocol OpenAIMCPOAuthStorage {
    func load(providerID: String, serverID: UUID) -> OpenAIMCPOAuthCredential?
    func save(_ credential: OpenAIMCPOAuthCredential?, providerID: String, serverID: UUID) throws
}

private struct OAuthKeychainStorage: OpenAIMCPOAuthStorage {
    func load(providerID: String, serverID: UUID) -> OpenAIMCPOAuthCredential? {
        CredentialStore.mcpOAuth(providerID: providerID, serverID: serverID)
    }
    func save(_ credential: OpenAIMCPOAuthCredential?, providerID: String, serverID: UUID) throws {
        try CredentialStore.saveMCPOAuth(credential, providerID: providerID, serverID: serverID)
    }
}

@MainActor
final class OpenAIMCPOAuthManager {
    static let shared = OpenAIMCPOAuthManager()
    private struct Key: Hashable { let providerID: String; let serverID: UUID }
    private struct Pending { let id: UUID; let task: Task<String, any Error> }
    private var pending: [Key: Pending] = [:]
    private let transport: any OpenAIMCPOAuthTransport
    private let storage: any OpenAIMCPOAuthStorage
    private let now: () -> Date

    init(transport: any OpenAIMCPOAuthTransport = OpenAIMCPOAuthHTTP(), storage: (any OpenAIMCPOAuthStorage)? = nil, now: @escaping () -> Date = Date.init) {
        self.transport = transport
        self.storage = storage ?? OAuthKeychainStorage()
        self.now = now
    }

    func authorize(server: OpenAIMCPServer, authenticate: (URL) async throws -> URL) async throws -> OpenAIMCPOAuthCredential {
        guard let configuration = server.oauth else { throw OpenAIMCPOAuthFailure.configuration }
        let metadata = try await discover(configuration)
        let attempt = try OpenAIMCPOAuthAttempt(configuration: configuration, metadata: metadata)
        try Task.checkCancellation()
        let callback = try await authenticate(attempt.authorizationURL())
        try Task.checkCancellation()
        let response = try await exchange(endpoint: metadata.token, fields: attempt.exchangeFields(callback: callback))
        try Task.checkCancellation()
        return try .init(response: response, binding: configuration.binding(destination: server.destination), endpoint: metadata.token, now: now())
    }

    func commit(_ credential: OpenAIMCPOAuthCredential, server: OpenAIMCPServer, providerID: String) throws {
        guard let configuration = server.oauth, credential.binding == (try configuration.binding(destination: server.destination)) else { throw OpenAIMCPOAuthFailure.configuration }
        try storage.save(credential, providerID: providerID, serverID: server.id)
        let key = Key(providerID: providerID, serverID: server.id)
        pending.removeValue(forKey: key)?.task.cancel()
    }

    func disconnect(serverID: UUID, providerID: String) throws {
        try storage.save(nil, providerID: providerID, serverID: serverID)
        pending.removeValue(forKey: Key(providerID: providerID, serverID: serverID))?.task.cancel()
    }

    func accessToken(server: OpenAIMCPServer, providerID: String) async throws -> String {
        try Task.checkCancellation()
        guard let configuration = server.oauth,
              let original = storage.load(providerID: providerID, serverID: server.id),
              original.sessionID == server.authorizationRevision,
              original.binding == (try configuration.binding(destination: server.destination)) else { throw OpenAIMCPOAuthFailure.signIn }
        try configuration.validate()
        if original.expiresAt.map({ $0 > now().addingTimeInterval(60) }) ?? true {
            return original.accessToken
        }
        let key = Key(providerID: providerID, serverID: server.id)
        if let existing = pending[key] {
            let token = try await existing.task.value
            try Task.checkCancellation()
            return token
        }
        guard let refresh = original.refreshToken else { throw OpenAIMCPOAuthFailure.signIn }
        let id = UUID()
        let task = Task { @MainActor in
            var fields = ["grant_type": "refresh_token", "refresh_token": refresh, "client_id": configuration.clientID]
            if !configuration.resource.isEmpty { fields["resource"] = configuration.resource }
            let response = try await self.exchange(endpoint: original.tokenEndpoint, fields: fields)
            try Task.checkCancellation()
            guard self.storage.load(providerID: providerID, serverID: server.id) == original else { throw OpenAIMCPOAuthFailure.signIn }
            let updated = try OpenAIMCPOAuthCredential(response: response, binding: original.binding, endpoint: original.tokenEndpoint, previous: original, now: self.now())
            try self.storage.save(updated, providerID: providerID, serverID: server.id)
            return updated.accessToken
        }
        pending[key] = .init(id: id, task: task)
        defer { if pending[key]?.id == id { pending[key] = nil } }
        let token = try await task.value
        try Task.checkCancellation()
        return token
    }

    func discover(_ configuration: OpenAIMCPOAuthConfiguration) async throws -> OpenAIMCPOAuthMetadata {
        for url in try configuration.metadataURLs() {
            try Task.checkCancellation()
            let result = try await transport.send(URLRequest(url: url))
            if [404, 410].contains(result.status) {
                continue
            }
            guard (200..<300).contains(result.status), let json = try? OpenAIJSON.decode(result.data) else { throw OpenAIMCPOAuthFailure.metadata }
            return try .init(json, configuration: configuration)
        }
        throw OpenAIMCPOAuthFailure.metadata
    }

    private func exchange(endpoint: URL, fields: [String: String]) async throws -> OpenAIJSON {
        _ = try OpenAIMCPOAuthConfiguration.https(endpoint.absoluteString)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = OpenAIMCPOAuthAttempt.form(fields)
        let result = try await transport.send(request)
        guard let json = try? OpenAIJSON.decode(result.data) else { throw OpenAIMCPOAuthFailure.token }
        if result.status == 400, json["error"] == "invalid_grant" { throw OpenAIMCPOAuthFailure.signIn }
        guard (200..<300).contains(result.status) else { throw OpenAIMCPOAuthFailure.token }
        return json
    }
}
