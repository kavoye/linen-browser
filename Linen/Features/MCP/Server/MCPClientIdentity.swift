// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import Security

nonisolated struct MCPClientIdentity: Sendable, Equatable {
    let name: String
    let path: String
    let developer: String?

    static func ofPeer(socket descriptor: Int32) -> MCPClientIdentity? {
        var token = audit_token_t()
        var length = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &length) == 0 else { return nil }
        var peer: pid_t = 0
        var pidLength = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERPID, &peer, &pidLength) == 0 else { return nil }
        let tokenData = withUnsafeBytes(of: &token) { Data($0) }
        guard let relay = code(attributes: [kSecGuestAttributeAudit: tokenData]), let relayPath = path(of: relay) else { return nil }
        guard relayPath == Bundle.main.executableURL?.resolvingSymlinksInPath().path else {
            return identity(of: relay, path: relayPath)
        }
        guard let parent = parentPID(of: peer), parent > 1,
              let client = code(attributes: [kSecGuestAttributePid: parent]), let clientPath = path(of: client)
        else { return nil }
        return identity(of: client, path: clientPath)
    }

    private static func identity(of code: SecCode, path: String) -> MCPClientIdentity {
        MCPClientIdentity(name: displayName(forExecutable: path), path: path, developer: verifiedDeveloper(of: code))
    }

    private static func code(attributes: [CFString: Any]) -> SecCode? {
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes as CFDictionary, [], &code) == errSecSuccess else { return nil }
        return code
    }

    private static func path(of code: SecCode) -> String? {
        var staticCode: SecStaticCode?
        var url: CFURL?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopyPath(staticCode, [], &url) == errSecSuccess, let url = url as URL?
        else { return nil }
        let resolved = url.resolvingSymlinksInPath()
        guard resolved.pathExtension == "app", let executable = Bundle(url: resolved)?.executableURL else { return resolved.path }
        return executable.resolvingSymlinksInPath().path
    }

    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbi_ppid)
    }

    private static func verifiedDeveloper(of code: SecCode) -> String? {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple generic" as CFString, [], &requirement) == errSecSuccess,
              SecCodeCheckValidity(code, [], requirement) == errSecSuccess
        else { return nil }
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let info = info as? [CFString: Any]
        else { return nil }
        if let certificate = (info[kSecCodeInfoCertificates] as? [SecCertificate])?.first,
           let summary = SecCertificateCopySubjectSummary(certificate) as String? {
            return organization(fromSummary: summary)
        }
        return info[kSecCodeInfoTeamIdentifier] as? String
    }

    static func organization(fromSummary summary: String) -> String {
        for prefix in ["Developer ID Application: ", "Apple Development: ", "Apple Distribution: "] where summary.hasPrefix(prefix) {
            let rest = summary.dropFirst(prefix.count)
            if let team = rest.range(of: " (", options: .backwards) {
                return String(rest[..<team.lowerBound])
            }
            return String(rest)
        }
        return summary
    }

    static func displayName(forExecutable path: String) -> String {
        let url = URL(fileURLWithPath: path)
        var bundle = url
        while bundle.path != "/" {
            bundle.deleteLastPathComponent()
            if bundle.pathExtension == "app", let info = Bundle(url: bundle)?.infoDictionary {
                let name = info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String
                if let name, !name.isEmpty {
                    return name
                }
            }
        }
        return url.lastPathComponent
    }
}
