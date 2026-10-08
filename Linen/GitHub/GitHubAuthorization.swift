// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Security

nonisolated struct GitHubDeviceCode: Decodable, Equatable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationUri: URL
    let expiresIn: Int
    let interval: Int
}

nonisolated enum GitHubAuthorizationResult: Sendable {
    case pending, slowDown
    case authorized(String)
}

nonisolated struct GitHubAuthorization: Sendable {
    let clientID: String
    let transport: GitHubClient.Transport

    static var configuredClientID: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "GitHubOAuthClientID") as? String ?? ""
        return value.contains("$(") ? "" : value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(clientID: String = Self.configuredClientID, transport: @escaping GitHubClient.Transport = GitHubClient.send) {
        self.clientID = clientID
        self.transport = transport
    }

    func begin(includePrivate: Bool) async throws -> GitHubDeviceCode {
        guard !clientID.isEmpty else { throw GitHubFailure.notConfigured }
        let data = try await post(path: "/login/device/code", values: [
            "client_id": clientID,
            "scope": includePrivate ? "read:user read:org notifications repo" : "read:user read:org notifications",
        ])
        let code = try GitHubClient.decoder().decode(GitHubDeviceCode.self, from: data)
        guard code.verificationUri.absoluteString == "https://github.com/login/device",
              code.expiresIn > 0, code.expiresIn <= 3600, code.interval > 0, code.interval <= code.expiresIn,
              !code.userCode.isEmpty, !code.deviceCode.isEmpty else {
            throw GitHubFailure.invalidResponse
        }
        return code
    }

    func poll(_ code: GitHubDeviceCode) async throws -> GitHubAuthorizationResult {
        let data: Data
        do {
            data = try await post(path: "/login/oauth/access_token", values: [
                "client_id": clientID,
                "device_code": code.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])
        } catch let error as URLError where error.code == .cancelled {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .pending
        }
        let result = try GitHubClient.decoder().decode(Response.self, from: data)
        if let token = result.accessToken, !token.isEmpty, !token.contains(where: { $0.isWhitespace }) {
            return .authorized(token)
        }
        switch result.error {
        case "authorization_pending":
            return .pending
        case "slow_down":
            return .slowDown
        case "expired_token":
            throw GitHubFailure.expired
        case "access_denied":
            throw GitHubFailure.denied
        default:
            throw GitHubFailure.api(String(localized: "GitHub sign-in failed. Check the OAuth app’s device flow setting."))
        }
    }

    private func post(path: String, values: [String: String]) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://github.com" + path)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(values.sorted { $0.key < $1.key }.map { key, value in
            key + "=" + (value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
        }.joined(separator: "&").utf8)
        let (data, response) = try await transport(request)
        guard (200..<300).contains(response.statusCode) else {
            throw GitHubFailure.api(String(localized: "GitHub sign-in is unavailable. Try again later."))
        }
        return data
    }

    private struct Response: Decodable {
        let accessToken: String?
        let error: String?
    }
}

nonisolated struct GitHubConnectionStore: Sendable {
    let profileID: UUID
    var storage: CredentialStore.Storage = .keychain

    private var account: String {
        "github-oauth:\(profileID.uuidString)"
    }

    func read() -> String? {
        storage.read(account)
    }

    func save(_ token: String?) throws {
        let status = token.map { storage.write($0, account) } ?? storage.delete(account)
        guard status == errSecSuccess || (token == nil && status == errSecItemNotFound) else {
            throw GitHubFailure.storage
        }
    }
}
