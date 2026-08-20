// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// The update layer's judgement calls: how a GitHub release payload is
/// read, and what the banner tells the user at each phase.
@MainActor
struct UpdateSurfaceTests {
    private func decode(_ json: String) throws -> GitHubRelease {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GitHubRelease.self, from: Data(json.utf8))
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

        let api = UpdateFeed.releaseAPI(tag: "v9.9").absoluteString
        #expect(api.contains("/releases/tags/v9.9"))

        let issue = UpdateFeed.newIssueURL.absoluteString
        #expect(issue.contains("\(UpdateFeed.owner)/\(UpdateFeed.repository)"))
        #expect(issue.hasSuffix("/issues/new/choose"))
    }

    /// Sparkle reads `SUFeedURL` from the bundle; the notes sheet reads the
    /// constants. They name the same repository or the app updates from one
    /// place and reports from another, which no amount of internal
    /// consistency in `UpdateFeed` can catch.
    @Test func theBundleAgreesWithTheFeedConstants() throws {
        let declared = try #require(
            Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        )
        #expect(declared == UpdateFeed.appcastURL.absoluteString)
    }
}
