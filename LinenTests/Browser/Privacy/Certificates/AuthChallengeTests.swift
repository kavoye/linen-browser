// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@MainActor
struct AuthChallengeTests {
    private func space(
        method: String,
        host: String = "example.com"
    ) -> URLProtectionSpace {
        URLProtectionSpace(
            host: host,
            port: 443,
            protocol: "https",
            realm: nil,
            authenticationMethod: method
        )
    }

    @Test func serverTrustGoesToCertificateEvaluation() {
        #expect(
            AuthChallenge.decision(
                for: space(method: NSURLAuthenticationMethodServerTrust),
                previousFailureCount: 0
            ) == .evaluateServerTrust
        )
    }

    @Test func serverTrustIsNeverRejectedForFailures() {
        #expect(
            AuthChallenge.decision(
                for: space(method: NSURLAuthenticationMethodServerTrust),
                previousFailureCount: 5
            ) == .evaluateServerTrust
        )
    }

    @Test(arguments: [
        NSURLAuthenticationMethodHTTPBasic,
        NSURLAuthenticationMethodHTTPDigest,
        NSURLAuthenticationMethodNTLM,
    ])
    func passwordMethodsPrompt(method: String) {
        #expect(
            AuthChallenge.decision(for: space(method: method), previousFailureCount: 0)
                == .promptForCredential
        )
    }

    @Test func secondFailureStillPrompts() {
        #expect(
            AuthChallenge.decision(
                for: space(method: NSURLAuthenticationMethodHTTPBasic),
                previousFailureCount: 2
            ) == .promptForCredential
        )
    }

    @Test func thirdFailureRejectsInsteadOfRepromptingForever() {
        #expect(
            AuthChallenge.decision(
                for: space(method: NSURLAuthenticationMethodHTTPBasic),
                previousFailureCount: 3
            ) == .rejectProtectionSpace
        )
    }

    @Test(arguments: [
        NSURLAuthenticationMethodClientCertificate,
        NSURLAuthenticationMethodNegotiate,
        NSURLAuthenticationMethodHTMLForm,
    ])
    func nonPasswordMethodsUseDefaultHandling(method: String) {
        #expect(
            AuthChallenge.decision(for: space(method: method), previousFailureCount: 0)
                == .useDefaultHandling
        )
    }

    @Test func passwordBasedMatchesTheThreeInteractiveMethods() {
        #expect(AuthChallenge.isPasswordBased(NSURLAuthenticationMethodHTTPBasic))
        #expect(AuthChallenge.isPasswordBased(NSURLAuthenticationMethodHTTPDigest))
        #expect(AuthChallenge.isPasswordBased(NSURLAuthenticationMethodNTLM))
        #expect(!AuthChallenge.isPasswordBased(NSURLAuthenticationMethodServerTrust))
        #expect(!AuthChallenge.isPasswordBased(NSURLAuthenticationMethodClientCertificate))
        #expect(!AuthChallenge.isPasswordBased(NSURLAuthenticationMethodHTMLForm))
    }
}
