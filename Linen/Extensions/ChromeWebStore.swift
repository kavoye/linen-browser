// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum ChromeWebStore {
    static let chromeVersion = "139.0.0.0"

    enum InstallError: LocalizedError {
        case badDownloadURL
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .badDownloadURL:
                String(localized: "Couldn’t build the download URL")
            case .httpStatus(let code):
                String(localized: "The Chrome Web Store returned HTTP \(code)")
            }
        }
    }

    static func extensionID(fromPageURL urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let host = url.host(),
              host == "chromewebstore.google.com" || host.hasSuffix(".chromewebstore.google.com") else {
            return nil
        }
        let parts = url.path().split(separator: "/")
        guard parts.first == "detail", let last = parts.last.map(String.init),
              last.count == 32, last.allSatisfy({ ("a"..."p").contains($0) }) else {
            return nil
        }
        return last
    }

    static func downloadURL(for id: String) -> URL? {
        URL(string: "https://clients2.google.com/service/update2/crx?response=redirect"
            + "&prodversion=\(chromeVersion)&acceptformat=crx3&x=id%3D\(id)%26uc")
    }

    static func downloadPackage(id: String) async throws -> Data {
        guard let url = downloadURL(for: id) else { throw InstallError.badDownloadURL }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw InstallError.httpStatus(http.statusCode)
        }
        return try CRXVerifier.verifiedZip(from: data, expectedID: id)
    }
}
