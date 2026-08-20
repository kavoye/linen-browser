// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum UpdateFeed {
    static let owner = "kavoye"
    static let repository = "linen-browser"

    static let appcastURL = URL(
        string: "https://github.com/\(owner)/\(repository)/releases/latest/download/appcast.xml"
    )!

    // A name of its own: a `tip` release that loses its pre-release flag becomes "latest", and one shared name would then serve previews to everyone.
    static let previewAppcastURL = URL(
        string: "https://github.com/\(owner)/\(repository)/releases/download/tip/appcast-tip.xml"
    )!

    static func appcastURL(for channel: UpdateChannel) -> URL {
        switch channel {
        case .release:
            appcastURL
        case .preview:
            previewAppcastURL
        }
    }

    static let newIssueURL = URL(
        string: "https://github.com/\(owner)/\(repository)/issues/new/choose"
    )!

    static let releasesURL = URL(
        string: "https://github.com/\(owner)/\(repository)/releases"
    )!

    /// One page holds every version this project has shipped so far.
    static let releasePageSize = 100

    static func releasesAPI(perPage: Int = releasePageSize) -> URL {
        URL(
            string: "https://api.github.com/repos/\(owner)/\(repository)/releases?per_page=\(perPage)"
        )!
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}
