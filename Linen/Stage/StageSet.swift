// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

#if DEBUG
import Foundation

@MainActor
enum StageSet {
    nonisolated struct Site: Sendable {
        let title: String
        let address: String

        var url: URL? {
            URL(string: address)
        }
    }

    nonisolated struct Group: Sendable {
        let name: String
        let color: TabFolderColor
        let sites: [Site]
    }

    nonisolated struct PastVisit: Sendable {
        let site: Site
        let hoursAgo: Double
        let visitCount: Int

        init(_ site: Site, hoursAgo: Double, visitCount: Int = 1) {
            self.site = site
            self.hoursAgo = hoursAgo
            self.visitCount = visitCount
        }
    }

    nonisolated struct StagedDownload: Sendable {
        let filename: String
        let host: String
        let bytes: Int64
        let finished: Bool
    }

    // MARK: - Sidebar

    static let pinned: [Site] = [
        Site(title: "Hacker News", address: "https://news.ycombinator.com/"),
        Site(title: "GitHub", address: "https://github.com/"),
    ]

    static let opening = Site(
        title: "macOS Tahoe",
        address: "https://www.apple.com/macos/"
    )

    static let video = Site(
        title: "Northern Lights over Mývatn",
        address: "https://upload.wikimedia.org/wikipedia/commons/f/f4/"
            + "002_Northern_lights_in_the_night_sky_over_M%C3%BDvatn_in_Iceland_Video_by_Giles_Laurent.webm"
    )

    static let loose: [Site] = [
        Site(
            title: "backdrop-filter",
            address: "https://developer.mozilla.org/en-US/docs/Web/CSS/backdrop-filter"
        ),
        video,
        Site(title: "NASA Image of the Day", address: "https://www.nasa.gov/image-of-the-day/"),
        opening,
    ]

    static let reading = Group(
        name: "Reading",
        color: .teal,
        sites: [
            Site(
                title: "Materials",
                address: "https://developer.apple.com/design/human-interface-guidelines/materials"
            ),
            Site(title: "Bauhaus", address: "https://en.wikipedia.org/wiki/Bauhaus"),
            Site(title: "The Swift Programming Language", address: "https://docs.swift.org/swift-book/"),
        ]
    )

    static let shipping = Group(
        name: "Ship 1.0",
        color: .orange,
        sites: [
            Site(title: "swift-evolution", address: "https://github.com/swiftlang/swift-evolution"),
            Site(title: "Swift Forums", address: "https://forums.swift.org/"),
        ]
    )

    // MARK: - History

    static let history: [PastVisit] = [
        PastVisit(Site(title: "Swift Forums", address: "https://forums.swift.org/"), hoursAgo: 1.2, visitCount: 9),
        PastVisit(
            Site(title: "WWDC Videos", address: "https://developer.apple.com/videos/"),
            hoursAgo: 2.4,
            visitCount: 3
        ),
        PastVisit(
            Site(title: "SF Symbols", address: "https://developer.apple.com/sf-symbols/"),
            hoursAgo: 3.1
        ),
        PastVisit(
            Site(title: "WebKit Features in Safari", address: "https://webkit.org/blog/"),
            hoursAgo: 5.5,
            visitCount: 4
        ),
        PastVisit(Site(title: "Hacker News", address: "https://news.ycombinator.com/"), hoursAgo: 6.0, visitCount: 22),
        PastVisit(
            Site(title: "Typographica — Reviews", address: "https://typographica.org/typeface-reviews/"),
            hoursAgo: 26,
            visitCount: 2
        ),
        PastVisit(
            Site(title: "Bauhaus", address: "https://en.wikipedia.org/wiki/Bauhaus"),
            hoursAgo: 27.5
        ),
        PastVisit(
            Site(title: "NASA Image of the Day", address: "https://www.nasa.gov/image-of-the-day/"),
            hoursAgo: 29,
            visitCount: 6
        ),
        PastVisit(
            Site(title: "Grid — MDN", address: "https://developer.mozilla.org/en-US/docs/Web/CSS/grid"),
            hoursAgo: 31
        ),
        PastVisit(
            Site(title: "swift-evolution", address: "https://github.com/swiftlang/swift-evolution"),
            hoursAgo: 50,
            visitCount: 7
        ),
        PastVisit(
            Site(title: "Human Interface Guidelines", address: "https://developer.apple.com/design/human-interface-guidelines"),
            hoursAgo: 52
        ),
        PastVisit(
            Site(title: "The Swift Programming Language", address: "https://docs.swift.org/swift-book/"),
            hoursAgo: 73,
            visitCount: 5
        ),
    ]

    static let downloads: [StagedDownload] = [
        StagedDownload(filename: "swift-6.2-osx.pkg", host: "download.swift.org", bytes: 24_117_248, finished: true),
        StagedDownload(filename: "materials-reference.pdf", host: "developer.apple.com", bytes: 3_884_106, finished: true),
        StagedDownload(filename: "aurora-australis.webm", host: "upload.wikimedia.org", bytes: 41_226_240, finished: false),
    ]
}

#endif
