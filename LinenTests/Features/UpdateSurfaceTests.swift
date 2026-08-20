// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Testing

@testable import Linen

/// The update layer's judgement calls: how a GitHub release payload is
/// read, and what the banner tells the user at each phase.
@MainActor
struct UpdateSurfaceTests {
    private func decode(_ json: String) throws -> GitHubRelease {
        try decoder().decode(GitHubRelease.self, from: Data(json.utf8))
    }

    private func decodeList(_ json: String) throws -> [GitHubRelease] {
        try decoder().decode([GitHubRelease].self, from: Data(json.utf8))
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    @Test func readsAGitHubReleasePayload() throws {
        let release = try decode("""
        {
          "tag_name": "v1.2",
          "name": "Summer release",
          "body": "- Faster\\n- Smaller",
          "html_url": "https://github.com/kavoye/linen-browser/releases/tag/v1.2",
          "published_at": "2026-08-01T12:00:00Z"
        }
        """)

        #expect(release.tagName == "v1.2")
        #expect(release.displayTitle == "Summer release")
        #expect(release.body?.contains("Faster") == true)
        #expect(release.publishedAt != nil)
    }

    /// GitHub lets a release go out untitled; the tag is always there to
    /// stand in.
    @Test func anUntitledReleaseIsNamedByItsTag() throws {
        let unnamed = try decode("""
        {"tag_name": "v1.3", "html_url": "https://example.com"}
        """)
        #expect(unnamed.displayTitle == "v1.3")

        let blank = try decode("""
        {"tag_name": "v1.4", "name": "   ", "html_url": "https://example.com"}
        """)
        #expect(blank.displayTitle == "v1.4")
    }

    /// The page is the whole history, so the payload is a list. GitHub sends
    /// the flags on every entry; a payload without them is still readable.
    @Test func readsAListOfReleases() throws {
        let releases = try decodeList("""
        [
          {"tag_name": "v1.2", "html_url": "https://example.com/2",
           "published_at": "2026-08-01T12:00:00Z", "prerelease": false, "draft": false},
          {"tag_name": "v1.1", "html_url": "https://example.com/1",
           "published_at": "2026-07-01T12:00:00Z", "prerelease": false, "draft": false}
        ]
        """)

        #expect(releases.map(\.tagName) == ["v1.2", "v1.1"])
        #expect(releases.allSatisfy { !$0.isPrerelease && !$0.isDraft })

        let bare = try decode(#"{"tag_name": "v1.0", "html_url": "https://example.com"}"#)
        #expect(!bare.isPrerelease)
        #expect(!bare.isDraft)
    }

    /// The rolling `tip` pre-release is one entry that never stops moving, and
    /// a draft belongs to whoever is writing it. Neither is a version shipped.
    @Test func theHistoryHoldsShippedVersionsNewestFirst() throws {
        let releases = try decodeList("""
        [
          {"tag_name": "tip", "html_url": "https://example.com/tip",
           "published_at": "2026-08-20T12:00:00Z", "prerelease": true, "draft": false},
          {"tag_name": "v1.1", "html_url": "https://example.com/1",
           "published_at": "2026-07-01T12:00:00Z", "prerelease": false, "draft": false},
          {"tag_name": "v1.3", "html_url": "https://example.com/3",
           "published_at": "2026-08-10T12:00:00Z", "prerelease": false, "draft": true},
          {"tag_name": "v1.2", "html_url": "https://example.com/2",
           "published_at": "2026-08-01T12:00:00Z", "prerelease": false, "draft": false}
        ]
        """)

        let shipped = ReleaseNotesModel.published(releases)

        #expect(shipped.map(\.tagName) == ["v1.2", "v1.1"])
    }

    /// A tag names its version with or without the `v`, and the running build
    /// is the one the page badges.
    @Test func aTagNamesItsVersionEitherWay() throws {
        let prefixed = try decode(#"{"tag_name": "v0.1.1", "html_url": "https://example.com"}"#)
        let bare = try decode(#"{"tag_name": "0.1.1", "html_url": "https://example.com"}"#)

        #expect(prefixed.version == "0.1.1")
        #expect(bare.version == "0.1.1")
        #expect(prefixed.version != "0.1.2")
    }

    @Test func theBannerNamesEachPhase() {
        let model = UpdateModel()
        model.version = "2.0"

        model.phase = .available
        #expect(UpdatePhrasing.title(model) == "Update to 2.0")
        #expect(UpdatePhrasing.caption(model)?.contains("2.0") == true)

        model.phase = .readyToInstall
        #expect(UpdatePhrasing.title(model) == "Update 2.0 ready")

        model.phase = .failed("No route to host")
        #expect(UpdatePhrasing.caption(model) == "No route to host")
    }

    /// Quiet until there is something worth saying, and quiet again once
    /// dismissed - except that a dismissal must not swallow a later phase.
    @Test func theBannerKnowsWhenToAppear() {
        let model = UpdateModel()

        #expect(!model.isBannerVisible)
        model.phase = .checking
        #expect(!model.isBannerVisible)

        model.phase = .available
        #expect(model.isBannerVisible)

        model.isDismissed = true
        #expect(!model.isBannerVisible)
    }

    /// RELEASING.md's contract: the feed is a permalink into this
    /// repository's latest release, so hosting never needs a web server.
    @Test func theFeedPointsAtTheRepositorysLatestRelease() {
        let feed = UpdateFeed.appcastURL.absoluteString
        #expect(feed.contains("\(UpdateFeed.owner)/\(UpdateFeed.repository)"))
        #expect(feed.hasSuffix("/releases/latest/download/appcast.xml"))

        let api = UpdateFeed.releasesAPI().absoluteString
        #expect(api.contains("/repos/\(UpdateFeed.owner)/\(UpdateFeed.repository)/releases"))
        #expect(api.hasSuffix("per_page=\(UpdateFeed.releasePageSize)"))

        let list = UpdateFeed.releasesURL.absoluteString
        #expect(list.hasSuffix("\(UpdateFeed.owner)/\(UpdateFeed.repository)/releases"))

        let issue = UpdateFeed.newIssueURL.absoluteString
        #expect(issue.contains("\(UpdateFeed.owner)/\(UpdateFeed.repository)"))
        #expect(issue.hasSuffix("/issues/new/choose"))
    }

    /// Sparkle reads `SUFeedURL` from the bundle; the notes sheet reads the
    /// constants. They name the same repository or the app updates from one
    /// place and reports from another, which no amount of internal
    /// consistency in `UpdateFeed` can catch.
    /// The caption says what the chosen channel does, not what the other one
    /// would give you — the row is a description of the current setting.
    @Test func eachChannelDescribesItself() {
        let release = String(localized: UpdateChannel.release.caption)
        let preview = String(localized: UpdateChannel.preview.caption)

        #expect(release != preview)
        #expect(!release.localizedCaseInsensitiveContains("preview"))
        #expect(preview.localizedCaseInsensitiveContains("preview"))
    }

    /// The caption sits on one line beside the pop-up menu. Two lines push the
    /// row taller than the ones around it.
    @Test func aChannelCaptionFitsBesideTheMenu() {
        let budget = SettingsMetrics.detailWidth
            - SettingsMetrics.cardInset * 2
            - 24
            - SettingsMetrics.controlWidth

        for channel in UpdateChannel.allCases {
            let width = (String(localized: channel.caption) as NSString)
                .size(withAttributes: [.font: NSFont.systemFont(ofSize: 11.5)])
                .width
            #expect(width <= budget)
        }
    }

    @Test func theBundleAgreesWithTheFeedConstants() throws {
        let declared = try #require(
            Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        )
        #expect(declared == UpdateFeed.appcastURL.absoluteString)
    }
}
