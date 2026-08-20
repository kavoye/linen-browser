// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import CryptoKit
import Foundation
import os
import Security

@MainActor
enum CertificateTrust {
    private static var accepted: [String: String] = [:]

    enum Decision {
        case useDefaultHandling
        case proceed(URLCredential)
        case cancel
    }

    static func decide(
        for challenge: URLAuthenticationChallenge,
        allowsExceptions: Bool,
        in window: NSWindow?
    ) async -> Decision {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = space.serverTrust
        else { return .useDefaultHandling }

        if SecTrustEvaluateWithError(trust, nil) {
            return .useDefaultHandling
        }

        let host = space.host.lowercased()
        guard let fingerprint = fingerprint(of: trust) else { return .useDefaultHandling }

        if accepted[host] == fingerprint {
            return .proceed(URLCredential(trust: trust))
        }

        guard allowsExceptions else { return .useDefaultHandling }

        let accepted = await ask(host: host, trust: trust, fingerprint: fingerprint, in: window)
        guard accepted else { return .cancel }

        Self.accepted[host] = fingerprint
        Pipeline.log.notice("certificate exception accepted for a host this session")
        return .proceed(URLCredential(trust: trust))
    }

    static func forgetAll() {
        accepted.removeAll()
    }

    static var acceptedHostCount: Int {
        accepted.count
    }

    // MARK: - Asking

    private static func ask(
        host: String,
        trust: SecTrust,
        fingerprint: String,
        in window: NSWindow?
    ) async -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = String(localized: "This website’s identity can’t be verified")
        alert.informativeText = detail(host: host, trust: trust, fingerprint: fingerprint)
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.addButton(withTitle: String(localized: "Continue")).hasDestructiveAction = true

        guard let window else {
            return alert.runModal() == .alertSecondButtonReturn
        }
        let response = await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
        }
        return response == .alertSecondButtonReturn
    }

    private static func detail(host: String, trust: SecTrust, fingerprint: String) -> String {
        var lines = [
            String(localized: "Linen can’t confirm that this certificate belongs to \(host). Somebody may be impersonating the website."),
            "",
        ]
        if let summary = leafSummary(of: trust) {
            lines.append(String(localized: "Issued to: \(summary)"))
        }
        lines.append(String(localized: "SHA-256: \(fingerprint)"))
        lines.append("")
        lines.append(String(localized: "Continue only if you expected this — a development server, or a proxy your organization runs. The exception lasts until you quit."))
        return lines.joined(separator: "\n")
    }

    private static func leafCertificate(of trust: SecTrust) -> SecCertificate? {
        (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first
    }

    private static func leafSummary(of trust: SecTrust) -> String? {
        guard let certificate = leafCertificate(of: trust) else { return nil }
        return SecCertificateCopySubjectSummary(certificate) as String?
    }

    static func fingerprint(of trust: SecTrust) -> String? {
        guard let certificate = leafCertificate(of: trust) else { return nil }
        return SHA256.hash(data: SecCertificateCopyData(certificate) as Data)
            .map { String(format: "%02X", $0) }
            .joined(separator: " ")
    }
}
