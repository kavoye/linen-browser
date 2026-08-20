// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

struct ResolvedVideo {
    let videoID: String?
    let fallbackURL: URL
}

@MainActor
final class YouTubeResolver {
    func resolve(query: String) async -> ResolvedVideo {
        let resultsURL = Self.resultsURL(for: query)
        var request = URLRequest(url: resultsURL, timeoutInterval: 2.5)
        request.setValue(WebViewPool.safariUserAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let html = String(data: data, encoding: .utf8),
                  let videoID = Self.firstVideoID(in: html)
            else {
                return ResolvedVideo(videoID: nil, fallbackURL: resultsURL)
            }
            Pipeline.log.info("YouTubeResolver: \(query, privacy: .private) → \(videoID, privacy: .public)")
            return ResolvedVideo(videoID: videoID, fallbackURL: resultsURL)
        } catch {
            Pipeline.log.warning("YouTubeResolver failed: \(error.localizedDescription, privacy: .public)")
            return ResolvedVideo(videoID: nil, fallbackURL: resultsURL)
        }
    }

    static func resultsURL(for query: String) -> URL {
        var components = URLComponents(string: "https://www.youtube.com/results")!
        components.queryItems = [URLQueryItem(name: "search_query", value: query)]
        return components.url!
    }

    static func firstVideoID(in html: String) -> String? {
        guard let range = html.range(
            of: #""videoId":"([0-9A-Za-z_-]{11})""#,
            options: .regularExpression
        ) else { return nil }
        return String(html[range].dropFirst(#""videoId":""#.count).dropLast())
    }
}
