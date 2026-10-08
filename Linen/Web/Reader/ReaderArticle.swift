// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct ReaderArticle: Equatable, Sendable {
    let url: URL
    let title: String
    let byline: String
    let siteName: String
    let excerpt: String
    let language: String
    let isRightToLeft: Bool
    let content: String
    let blocks: [String]

    var text: String {
        blocks.joined(separator: "\n\n")
    }

    var wordCount: Int {
        blocks.reduce(0) { $0 + $1.split(whereSeparator: \.isWhitespace).count }
    }

    var readingMinutes: Int {
        max(1, Int((Double(wordCount) / 230).rounded()))
    }

    init(
        url: URL,
        title: String,
        byline: String = "",
        siteName: String = "",
        excerpt: String = "",
        language: String = "",
        isRightToLeft: Bool = false,
        content: String,
        blocks: [String]
    ) {
        self.url = url
        self.title = title
        self.byline = byline
        self.siteName = siteName
        self.excerpt = excerpt
        self.language = language
        self.isRightToLeft = isRightToLeft
        self.content = content
        self.blocks = blocks
    }

    init?(json: String) {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let address = object["url"] as? String,
              let url = URL(string: address),
              let content = object["content"] as? String,
              let blocks = object["blocks"] as? [String],
              !blocks.isEmpty
        else { return nil }
        func field(_ key: String) -> String {
            (object[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        self.init(
            url: url,
            title: field("title"),
            byline: field("byline"),
            siteName: field("siteName"),
            excerpt: field("excerpt"),
            language: field("lang"),
            isRightToLeft: field("dir").lowercased() == "rtl",
            content: content,
            blocks: blocks
        )
    }
}
