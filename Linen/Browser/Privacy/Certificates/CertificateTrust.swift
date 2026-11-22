// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation
import os
import Security

@MainActor
enum CertificateTrust {
    private static var untrusted: [String: Warning] = [:]

    struct Warning {
        let site: String
        let fingerprint: String
        let trust: SecTrust
    }

    enum Decision {
        case useDefaultHandling
        case proceed(URLCredential)
        case warn(Warning)
    }

    static func decide(
        for challenge: URLAuthenticationChallenge,
        skipsWarning: Bool,
        accepted: [String: String]
    ) async -> Decision {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = space.serverTrust,
              let trusted = try? await evaluate(trust)
        else { return .useDefaultHandling }
        let site = site(host: space.host, port: space.port)
        if trusted {
            untrusted[site] = nil
            return .useDefaultHandling
        }

        guard let fingerprint = fingerprint(of: trust) else { return .useDefaultHandling }
        let warning = Warning(site: site, fingerprint: fingerprint, trust: trust)
        untrusted[site] = warning
        if skipsWarning || accepted[site] == fingerprint {
            return .proceed(URLCredential(trust: trust))
        }
        return .warn(warning)
    }

    static func warning(
        before url: URL,
        skipsWarning: Bool,
        accepted: [String: String]
    ) -> Warning? {
        guard !skipsWarning, url.scheme?.lowercased() == "https",
              let site = site(of: url),
              let warning = untrusted[site],
              accepted[site] != warning.fingerprint
        else { return nil }
        return warning
    }

    static func isUntrusted(_ url: URL?) -> Bool {
        guard let url, let site = site(of: url) else { return false }
        return untrusted[site] != nil
    }

    static func site(host: String, port: Int) -> String {
        let bare = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return "\(bare):\(port)"
    }

    static func origin(ofSite site: String) -> String? {
        let origin = SitePermissions.origin(for: URL(string: "https://\(site)"))
        return origin.isEmpty ? nil : origin
    }

    static func site(ofOrigin origin: String) -> String? {
        guard let url = URL(string: origin), url.scheme?.lowercased() == "https" else { return nil }
        return site(of: url)
    }

    static func site(of url: URL) -> String? {
        guard let host = url.host() else { return nil }
        let port = url.port ?? (url.scheme?.lowercased() == "http" ? 80 : 443)
        return site(host: host, port: port)
    }

    static func evaluate(
        _ trust: SecTrust,
        start: (SecTrust, DispatchQueue, @escaping SecTrustWithErrorCallback) -> OSStatus
            = SecTrustEvaluateAsyncWithError
    ) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            let status = start(trust, .main) { _, trusted, _ in
                continuation.resume(returning: trusted)
            }
            if status != errSecSuccess {
                continuation.resume(throwing: NSError(domain: NSOSStatusErrorDomain, code: Int(status)))
            }
        }
    }

    private static func leafCertificate(of trust: SecTrust) -> SecCertificate? {
        (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first
    }

    static func fingerprint(of trust: SecTrust) -> String? {
        guard let certificate = leafCertificate(of: trust) else { return nil }
        return SHA256.hash(data: SecCertificateCopyData(certificate) as Data)
            .map { String(format: "%02X", $0) }
            .joined(separator: " ")
    }
}
