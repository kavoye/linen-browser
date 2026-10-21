// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

@MainActor
@Observable
final class GitHubSignIn {
    private(set) var isConnecting = false
    private(set) var deviceCode: GitHubDeviceCode?

    @ObservationIgnored private let authorization: GitHubAuthorization
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var attempt = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    init(authorization: GitHubAuthorization, sleep: @escaping @Sendable (Duration) async throws -> Void) {
        self.authorization = authorization
        self.sleep = sleep
    }

    isolated deinit {
        task?.cancel()
    }

    func begin(
        includePrivate: Bool,
        open: @escaping @MainActor (URL) -> Void,
        authorized: @escaping @MainActor (String) async throws -> @MainActor () throws -> Void,
        failed: @escaping @MainActor (Error) -> Void
    ) {
        cancel()
        isConnecting = true
        let attempt = attempt
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if attempt == self.attempt {
                    isConnecting = false
                    deviceCode = nil
                }
            }
            do {
                let code = try await authorization.begin(includePrivate: includePrivate)
                guard attempt == self.attempt, !Task.isCancelled else { return }
                deviceCode = code
                open(code.verificationUri)
                let deadline = Date.now.addingTimeInterval(TimeInterval(code.expiresIn))
                var interval = max(5, code.interval)
                while Date.now < deadline {
                    try await sleep(.seconds(interval))
                    try Task.checkCancellation()
                    guard Date.now < deadline else { throw GitHubFailure.expired }
                    let result = try await authorization.poll(code)
                    guard attempt == self.attempt, !Task.isCancelled else { return }
                    switch result {
                    case .pending:
                        continue
                    case .slowDown:
                        interval += 5
                    case .authorized(let credential):
                        let commit = try await authorized(credential)
                        guard attempt == self.attempt, !Task.isCancelled else { return }
                        try commit()
                        return
                    }
                }
                throw GitHubFailure.expired
            } catch {
                if attempt == self.attempt, !Task.isCancelled {
                    failed(error)
                }
            }
        }
    }

    func cancel() {
        attempt += 1
        task?.cancel()
        task = nil
        isConnecting = false
        deviceCode = nil
    }
}
