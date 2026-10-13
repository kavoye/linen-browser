// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import AuthenticationServices
import Foundation

@MainActor
final class OpenAIMCPOAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let window: NSWindow
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, any Error>?
    private var timeout: Task<Void, Never>?
    private var identity: UUID?

    init(window: NSWindow) {
        self.window = window
    }

    func authenticate(_ url: URL) async throws -> URL {
        guard continuation == nil else { throw OpenAIMCPOAuthFailure.unavailable }
        let id = UUID()
        identity = id
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let session = ASWebAuthenticationSession(url: url, callback: .customScheme("com.kavoye.linen.oauth")) { @Sendable [weak self] callback, _ in
                    Task { @MainActor in
                        if let callback {
                            self?.finish(.success(callback), id: id)
                        } else {
                            self?.finish(.failure(OpenAIMCPOAuthFailure.cancelled), id: id)
                        }
                    }
                }
                self.session = session
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = true
                guard session.start() else {
                    finish(.failure(OpenAIMCPOAuthFailure.unavailable), id: id)
                    return
                }
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(300)) } catch { return }
                    self?.cancel(id: id)
                }
            }
        } onCancel: {
            Task { @MainActor in self.cancel(id: id) }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        window
    }

    private func cancel(id: UUID) {
        guard identity == id else { return }
        session?.cancel()
        finish(.failure(OpenAIMCPOAuthFailure.cancelled), id: id)
    }

    private func finish(_ result: Result<URL, any Error>, id: UUID) {
        guard identity == id else { return }
        identity = nil
        let pending = continuation
        continuation = nil
        timeout?.cancel()
        timeout = nil
        session = nil
        pending?.resume(with: result)
    }
}
