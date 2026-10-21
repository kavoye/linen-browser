// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct DocumentTitles {
    private var titles: [URL: String] = [:]

    func filename(for url: URL?) -> String? {
        url.flatMap { titles[Self.documentURL($0)] }
    }

    mutating func note(_ response: URLResponse) {
        guard let url = response.url.map(Self.documentURL) else { return }
        if response.mimeType?.lowercased() == "application/pdf",
           let filename = response.suggestedFilename, !filename.isEmpty {
            titles[url] = filename
        } else {
            titles[url] = nil
        }
    }

    private static func documentURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.fragment = nil
        return components.url ?? url
    }
}
