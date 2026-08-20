// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum UpdateFeed {
    static let owner = "kavoye"
    static let repository = "linen-browser"

    static let appcastURL = URL(
        string: "https://github.com/\(owner)/\(repository)/releases/latest/download/appcast.xml"
    )!

    static let newIssueURL = URL(
        string: "https://github.com/\(owner)/\(repository)/issues/new/choose"
    )!

    static func releaseAPI(tag: String) -> URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/tags/\(tag)")!
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}
