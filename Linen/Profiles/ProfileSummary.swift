// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

enum ProfileSummary {
    static func tabs(_ count: Int) -> String {
        guard count > 0 else { return String(localized: "No tabs") }
        return String(localized: "\(count) tabs")
    }

    static func size(_ bytes: Int64) -> String {
        guard bytes > 0 else { return String(localized: "No data stored") }
        return bytes.formatted(.byteCount(style: .file))
    }

    static let neverOpened = LocalizedStringResource("Never opened")

    static func tabsAndFolders(tabs count: Int, folders: Int) -> String {
        guard folders > 0 else { return tabs(count) }
        return [tabs(count), String(localized: "\(folders) folders")].joined(separator: " · ")
    }

    static func history(pages: Int, since: Date?) -> String {
        guard pages > 0 else { return String(localized: "No history") }
        var parts = [String(localized: "\(pages) pages of history")]
        if let since {
            parts.append(String(localized: "Since \(since.formatted(.dateTime.month(.wide).day()))"))
        }
        return parts.joined(separator: " · ")
    }

    static func extensions(_ count: Int) -> String {
        guard count > 0 else { return String(localized: "None installed") }
        return String(localized: "\(count) installed")
    }

    static func permissions(_ count: Int) -> String {
        guard count > 0 else { return String(localized: "All websites use the defaults") }
        return String(localized: "\(count) websites changed")
    }

    static func lastUsed(_ date: Date) -> String {
        String(localized: "Last used \(date.formatted(.relative(presentation: .named)))")
    }

    static let separated: [LocalizedStringResource] = [
        "Sign-ins and cookies",
        "History",
        "Tabs and folders",
        "Extensions",
        "Website permissions",
        "Search engine",
        "Start page",
        "Tracker blocking",
        "Assistant provider and key",
        "What the assistant may do",
        "Page zoom",
    ]
}
