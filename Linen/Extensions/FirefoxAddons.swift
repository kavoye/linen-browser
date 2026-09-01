// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation

nonisolated enum FirefoxAddons {
    enum InstallError: LocalizedError {
        case badDownloadURL
        case httpStatus(Int)
        case malformedListing
        case checksumMismatch

        var errorDescription: String? {
            switch self {
            case .badDownloadURL:
                String(localized: "Couldn’t build the download URL")
            case .httpStatus(let code):
                String(localized: "Firefox Add-ons returned HTTP \(code)")
            case .malformedListing:
                String(localized: "Firefox Add-ons returned an unreadable listing")
            case .checksumMismatch:
                String(localized: "The downloaded add-on didn’t match its checksum")
            }
        }
    }

    struct Listing: Equatable, Sendable {
        var version: String
        var fileURL: URL
        var sha256: String?
    }

    static func slug(fromPageURL urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let host = url.host(),
              host == "addons.mozilla.org" else {
            return nil
        }
        let parts = url.path().split(separator: "/").map(String.init)
        guard let at = parts.firstIndex(of: "addon"),
              at >= 1, parts[at - 1] == "firefox",
              parts.indices.contains(at + 1) else {
            return nil
        }
        let candidate = parts[at + 1]
        guard isValidSlug(candidate) else { return nil }
        return candidate
    }

    static func isValidSlug(_ slug: String) -> Bool {
        guard !slug.isEmpty, slug.count <= 100, !slug.hasPrefix(".") else { return false }
        return slug.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
    }

    static func listingURL(for slug: String) -> URL? {
        URL(string: "https://addons.mozilla.org/api/v5/addons/addon/\(slug)/?app=firefox")
    }

    static func listing(fromJSON data: Data) throws -> Listing {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = root["current_version"] as? [String: Any],
              let version = current["version"] as? String else {
            throw InstallError.malformedListing
        }
        let file = current["file"] as? [String: Any]
            ?? (current["files"] as? [[String: Any]])?.first
        guard let file,
              let address = file["url"] as? String,
              let fileURL = URL(string: address),
              fileURL.scheme == "https" else {
            throw InstallError.malformedListing
        }
        var sha256: String?
        if let hash = file["hash"] as? String, hash.hasPrefix("sha256:") {
            sha256 = String(hash.dropFirst("sha256:".count)).lowercased()
        }
        return Listing(version: version, fileURL: fileURL, sha256: sha256)
    }

    static func listing(for slug: String) async throws -> Listing {
        guard isValidSlug(slug), let url = listingURL(for: slug) else {
            throw InstallError.badDownloadURL
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw InstallError.httpStatus(http.statusCode)
        }
        return try listing(fromJSON: data)
    }

    static func matches(_ package: Data, sha256 expected: String?) -> Bool {
        guard let expected else { return true }
        let digest = SHA256.hash(data: package).map { String(format: "%02x", $0) }.joined()
        return digest == expected
    }

    static func downloadPackage(slug: String) async throws -> Data {
        let listed = try await listing(for: slug)
        let (data, response) = try await URLSession.shared.data(from: listed.fileURL)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw InstallError.httpStatus(http.statusCode)
        }
        guard matches(data, sha256: listed.sha256) else {
            throw InstallError.checksumMismatch
        }
        return data
    }
}
