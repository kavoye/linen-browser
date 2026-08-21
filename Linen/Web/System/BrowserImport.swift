// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

enum BrowserImport {
    struct Payload: Sendable {
        var bookmarks: [HistoryStore.Entry] = []
        var folderName = ""

        var isEmpty: Bool {
            bookmarks.isEmpty
        }

        var phrase: String {
            String(localized: "\(bookmarks.count) bookmarks")
        }
    }

    enum Failure: Error {
        case unreadable
    }

    nonisolated static var folderName: String {
        String(localized: "Imported Bookmarks")
    }

    // MARK: - Reading

    nonisolated static func read(_ file: URL) throws -> Payload {
        guard let data = try? Data(contentsOf: file), let text = decode(data) else {
            throw Failure.unreadable
        }
        return Payload(bookmarks: bookmarks(inHTML: text), folderName: folderName)
    }

    nonisolated static func decode(_ data: Data) -> String? {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252)
    }

    nonisolated static func isExport(_ html: String) -> Bool {
        html.range(of: "netscape-bookmark-file", options: .caseInsensitive) != nil
            || html.range(of: "<dt><a", options: .caseInsensitive) != nil
    }

    nonisolated static func bookmarks(inHTML html: String) -> [HistoryStore.Entry] {
        guard isExport(html) else { return [] }
        var found: [HistoryStore.Entry] = []
        var seen: Set<String> = []

        for match in link.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let attributes = Range(match.range(at: 1), in: html),
                  let label = Range(match.range(at: 2), in: html)
            else { continue }

            let tag = String(html[attributes])
            guard let url = value(of: href, in: tag), isWebPage(url), seen.insert(url).inserted else {
                continue
            }

            let title = text(in: String(html[label]))
            found.append(HistoryStore.Entry(
                url: url,
                title: title.isEmpty ? url : title,
                date: date(value(of: addDate, in: tag).flatMap(Double.init) ?? 0)
            ))
        }
        return found
    }

    nonisolated static func date(_ seconds: Double) -> Date {
        guard seconds > 0 else { return .distantPast }
        return Date(timeIntervalSince1970: seconds)
    }

    private nonisolated static func isWebPage(_ url: String) -> Bool {
        guard let scheme = URL(string: url)?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private nonisolated static func value(of pattern: NSRegularExpression, in tag: String) -> String? {
        let range = NSRange(tag.startIndex..., in: tag)
        guard let match = pattern.firstMatch(in: tag, range: range),
              let value = Range(match.range(at: 1), in: tag)
        else { return nil }
        return entities(in: String(tag[value]))
    }

    private nonisolated static func text(in label: String) -> String {
        let stripped = markup.stringByReplacingMatches(
            in: label,
            range: NSRange(label.startIndex..., in: label),
            withTemplate: ""
        )
        return entities(in: stripped).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func entities(in raw: String) -> String {
        let text = NSMutableString(string: raw)
        let matches = numeric.matches(in: raw, range: NSRange(raw.startIndex..., in: raw))
        for match in matches.reversed() {
            guard let digits = Range(match.range(at: 2), in: raw),
                  let code = UInt32(raw[digits], radix: match.range(at: 1).length > 0 ? 16 : 10),
                  let scalar = Unicode.Scalar(code)
            else { continue }
            text.replaceCharacters(in: match.range, with: String(Character(scalar)))
        }
        for (entity, character) in named {
            text.replaceOccurrences(
                of: entity,
                with: character,
                options: .caseInsensitive,
                range: NSRange(location: 0, length: text.length)
            )
        }
        return text as String
    }

    private nonisolated static let named = [
        ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"),
        ("&nbsp;", "\u{00A0}"), ("&amp;", "&"),
    ]

    private nonisolated static let link = regex("<a\\s+([^>]*)>(.*?)</a>")
    private nonisolated static let markup = regex("<[^>]*>")
    private nonisolated static let numeric = regex("&#(x?)([0-9a-f]+);")
    private nonisolated static let href = regex("href\\s*=\\s*\"([^\"]*)\"")
    private nonisolated static let addDate = regex("add_date\\s*=\\s*\"([^\"]*)\"")

    private nonisolated static func regex(_ pattern: String) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
    }

    // MARK: - Applying

    @MainActor
    static func apply(_ payload: Payload, into browser: BrowserModel) {
        browser.importBookmarksFolder(named: payload.folderName, entries: payload.bookmarks)
    }
}
