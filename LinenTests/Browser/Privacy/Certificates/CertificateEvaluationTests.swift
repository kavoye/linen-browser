// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Security
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized)
struct CertificateEvaluationTests {
    @Test func webKitCanSeeTheChallengeHandler() {
        let selector = NSSelectorFromString("webView:didReceiveAuthenticationChallenge:completionHandler:")
        #expect(TabNavigationDelegate.instancesRespond(to: selector))
    }

    @Test func trustedCertificateIsLeftToWebKit() async throws {
        let decision = await CertificateTrust.decide(
            for: try challenge(anchored: true), skipsWarning: false, accepted: [:]
        )
        guard case .useDefaultHandling = decision else {
            Issue.record("A trusted certificate must not be overridden")
            return
        }
    }

    @Test func untrustedCertificateWarns() async throws {
        let decision = await CertificateTrust.decide(
            for: try challenge(), skipsWarning: false, accepted: [:]
        )
        guard case .warn(let warning) = decision else {
            Issue.record("An untrusted certificate must warn")
            return
        }
        #expect(warning.site == "linen-trust-test.invalid:8765")
        #expect(CertificateTrust.site(of: URL(string: "https://Linen-Trust-Test.invalid:8765/x")!) == warning.site)
    }

    @Test func theSettingSkipsTheWarningButIsNotRemembered() async throws {
        let decision = await CertificateTrust.decide(
            for: try challenge(), skipsWarning: true, accepted: [:]
        )
        guard case .proceed = decision else {
            Issue.record("The setting must open the website without a warning")
            return
        }
        #expect(CertificateTrust.isUntrusted(URL(string: "https://linen-trust-test.invalid:8765/")))
        #expect(!CertificateTrust.isUntrusted(URL(string: "https://linen-trust-test.invalid/")))

        guard case .warn = await CertificateTrust.decide(
            for: try challenge(), skipsWarning: false, accepted: [:]
        ) else {
            Issue.record("Turning the setting off must warn again")
            return
        }
    }

    @Test func aReusedConnectionStillWarnsBeforeTheLoad() async throws {
        guard case .warn(let warning) = await CertificateTrust.decide(
            for: try challenge(), skipsWarning: false, accepted: [:]
        ) else {
            Issue.record("An untrusted certificate must warn")
            return
        }
        let url = try #require(URL(string: "https://linen-trust-test.invalid:8765/index.html"))
        #expect(CertificateTrust.warning(before: url, skipsWarning: false, accepted: [:])?.site == warning.site)
        #expect(CertificateTrust.warning(before: url, skipsWarning: true, accepted: [:]) == nil)
        #expect(CertificateTrust.warning(
            before: url, skipsWarning: false, accepted: [warning.site: warning.fingerprint]
        ) == nil)
        #expect(CertificateTrust.warning(
            before: try #require(URL(string: "https://linen-trust-test.invalid:8766/")),
            skipsWarning: false, accepted: [warning.site: warning.fingerprint]
        ) == nil)
        #expect(CertificateTrust.warning(
            before: try #require(URL(string: "http://linen-trust-test.invalid:8765/")),
            skipsWarning: false, accepted: [:]
        ) == nil)
    }

    @Test func acceptedCertificateProceedsOnlyWhileItMatches() async throws {
        guard case .warn(let warning) = await CertificateTrust.decide(
            for: try challenge(), skipsWarning: false, accepted: [:]
        ) else {
            Issue.record("An untrusted certificate must warn")
            return
        }
        guard case .proceed = await CertificateTrust.decide(
            for: try challenge(), skipsWarning: false, accepted: [warning.site: warning.fingerprint]
        ) else {
            Issue.record("An accepted certificate must not warn")
            return
        }
        guard case .warn = await CertificateTrust.decide(
            for: try challenge(), skipsWarning: false, accepted: [warning.site: "00"]
        ) else {
            Issue.record("A changed certificate must warn again")
            return
        }
    }

    private func challenge(anchored: Bool = false, port: Int = 8765) throws -> URLAuthenticationChallenge {
        let space = FixedTrustProtectionSpace(
            host: "linen-trust-test.invalid", port: port, protocol: "https", realm: nil,
            authenticationMethod: NSURLAuthenticationMethodServerTrust
        )
        space.trust = try makeTrust(anchored: anchored)
        return URLAuthenticationChallenge(
            protectionSpace: space, proposedCredential: nil, previousFailureCount: 0,
            failureResponse: nil, error: nil, sender: UnusedChallengeSender()
        )
    }

    @Test(arguments: [true, false])
    func evaluationPreservesTrustResult(anchored: Bool) async throws {
        let trust = try makeTrust(anchored: anchored)
        #expect(try await CertificateTrust.evaluate(trust) == anchored)
        #expect(try await CertificateTrust.evaluate(trust) == anchored)
    }

    @Test func mainQueueCanRunWhileEvaluationIsPending() async throws {
        let trust = try makeTrust()
        var didRunMainQueue = false
        let trusted = try await CertificateTrust.evaluate(trust) { trust, queue, completion in
            #expect(queue === DispatchQueue.main)
            DispatchQueue.main.async {
                didRunMainQueue = true
                completion(trust, true, nil)
            }
            return errSecSuccess
        }
        #expect(trusted)
        #expect(didRunMainQueue)
    }

    @Test func inlineCompletionResumesOnce() async throws {
        let trust = try makeTrust()
        let trusted = try await CertificateTrust.evaluate(trust) { trust, _, completion in
            completion(trust, false, nil)
            return errSecSuccess
        }
        #expect(!trusted)
    }

    @Test func startFailureDoesNotWaitForACallback() async throws {
        let trust = try makeTrust()
        do {
            _ = try await CertificateTrust.evaluate(trust) { _, _, _ in errSecParam }
            Issue.record("A failed start must throw")
        } catch {
            #expect((error as NSError).domain == NSOSStatusErrorDomain)
            #expect((error as NSError).code == Int(errSecParam))
        }
    }

    private func makeTrust(anchored: Bool = true) throws -> SecTrust {
        let data = try #require(Data(base64Encoded: Self.certificate))
        let certificate = try #require(SecCertificateCreateWithData(nil, data as CFData))
        var trust: SecTrust?
        #expect(SecTrustCreateWithCertificates(certificate, SecPolicyCreateBasicX509(), &trust) == errSecSuccess)
        let result = try #require(trust)
        #expect(SecTrustSetAnchorCertificates(result, (anchored ? [certificate] : []) as CFArray) == errSecSuccess)
        #expect(SecTrustSetAnchorCertificatesOnly(result, true) == errSecSuccess)
        #expect(SecTrustSetNetworkFetchAllowed(result, false) == errSecSuccess)
        #expect(SecTrustSetVerifyDate(result, Date(timeIntervalSince1970: 1_800_000_000) as CFDate) == errSecSuccess)
        return result
    }

    private static let certificate = """
        MIIBmzCCAUGgAwIBAgIUdeVwvca0ZsB/WOArBAp8Rd43EbAwCgYIKoZIzj0EAwIwIzEh
        MB8GA1UEAwwYbGluZW4tdHJ1c3QtdGVzdC5pbnZhbGlkMB4XDTI2MDkyMzA4MjUxM1oX
        DTM2MDkyMDA4MjUxM1owIzEhMB8GA1UEAwwYbGluZW4tdHJ1c3QtdGVzdC5pbnZhbGlk
        MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEAQ5kJDUiBcuROD3HNUBM+HesG2n/yLw+
        1lMRGwzXqvHcK5bPJ2HpngKhPVPpVNh14ajZxddF43B/l9n8+0qLh6NTMFEwHQYDVR0O
        BBYEFArGZPvXudxCdA105Q+6J+upaOooMB8GA1UdIwQYMBaAFArGZPvXudxCdA105Q+6
        J+upaOooMA8GA1UdEwEB/wQFMAMBAf8wCgYIKoZIzj0EAwIDSAAwRQIhAKpV/DtnSj4D
        FzBs8RaZI3ErneIJcFka2YsJvdAmw6hUAiBFdTXwJGvAe+N+nlHVAOrC9GEKxZ2exrRZ
        xpBn+P4otg==
        """.replacingOccurrences(of: "\n", with: "")
}

private nonisolated final class FixedTrustProtectionSpace: URLProtectionSpace, @unchecked Sendable {
    var trust: SecTrust?

    override var serverTrust: SecTrust? {
        trust
    }
}

private nonisolated final class UnusedChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
}
