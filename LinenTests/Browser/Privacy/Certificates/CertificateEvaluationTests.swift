// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Security
import Testing

@testable import Linen

@MainActor
struct CertificateEvaluationTests {
    @Test func disabledExceptionsLeaveValidationToWebKit() async {
        let space = UnevaluatedProtectionSpace(
            host: "example.com", port: 443, protocol: "https", realm: nil,
            authenticationMethod: NSURLAuthenticationMethodServerTrust
        )
        let challenge = URLAuthenticationChallenge(
            protectionSpace: space, proposedCredential: nil, previousFailureCount: 0,
            failureResponse: nil, error: nil, sender: UnusedChallengeSender()
        )
        let decision = await CertificateTrust.decide(for: challenge, allowsExceptions: false, in: nil)
        guard case .useDefaultHandling = decision else {
            Issue.record("WebKit must validate certificates when exceptions are disabled")
            return
        }
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

private nonisolated final class UnevaluatedProtectionSpace: URLProtectionSpace, @unchecked Sendable {
    override var serverTrust: SecTrust? {
        Issue.record("Disabled exceptions must not inspect or evaluate the server trust")
        return nil
    }
}

private nonisolated final class UnusedChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
}
