// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// Firefox add-ons install from addons.mozilla.org: the page URL names a slug,
/// the v5 API names the XPI and its checksum.
struct FirefoxAddonsTests {
    // MARK: - Page URLs

    @Test func aListingURLNamesItsSlug() {
        #expect(FirefoxAddons.slug(
            fromPageURL: "https://addons.mozilla.org/en-US/firefox/addon/ublock-origin/"
        ) == "ublock-origin")
        #expect(FirefoxAddons.slug(
            fromPageURL: "https://addons.mozilla.org/firefox/addon/violentmonkey/"
        ) == "violentmonkey")
        #expect(FirefoxAddons.slug(
            fromPageURL: "https://addons.mozilla.org/en-GB/firefox/addon/darkreader/reviews/"
        ) == "darkreader")
    }

    @Test func otherPagesOfferNoSlug() {
        #expect(FirefoxAddons.slug(fromPageURL: "https://addons.mozilla.org/en-US/firefox/extensions/") == nil)
        #expect(FirefoxAddons.slug(fromPageURL: "https://addons.mozilla.org/en-US/android/addon/ublock-origin/") == nil)
        #expect(FirefoxAddons.slug(fromPageURL: "https://example.org/en-US/firefox/addon/ublock-origin/") == nil)
        #expect(FirefoxAddons.slug(fromPageURL: "https://chromewebstore.google.com/detail/x/abc") == nil)
        #expect(FirefoxAddons.slug(fromPageURL: "not a url") == nil)
    }

    @Test func aSlugStaysWithinItsOwnDirectory() {
        #expect(FirefoxAddons.isValidSlug("ublock-origin"))
        #expect(FirefoxAddons.isValidSlug("tab_reloader"))
        #expect(!FirefoxAddons.isValidSlug("../escape"))
        #expect(!FirefoxAddons.isValidSlug(".hidden"))
        #expect(!FirefoxAddons.isValidSlug(""))
        #expect(!FirefoxAddons.isValidSlug("a/b"))
    }

    // MARK: - The listing

    @Test func aV5ListingNamesTheFileAndChecksum() throws {
        let json = Data("""
        { "current_version": { "version": "1.63.2",
          "file": { "url": "https://addons.mozilla.org/firefox/downloads/file/1/u.xpi",
                    "hash": "sha256:ABCDEF0123" } } }
        """.utf8)
        let listed = try FirefoxAddons.listing(fromJSON: json)
        #expect(listed.version == "1.63.2")
        #expect(listed.fileURL.absoluteString == "https://addons.mozilla.org/firefox/downloads/file/1/u.xpi")
        #expect(listed.sha256 == "abcdef0123")
    }

    @Test func anOlderListingWithAFilesArrayStillParses() throws {
        let json = Data("""
        { "current_version": { "version": "2.0",
          "files": [ { "url": "https://addons.mozilla.org/firefox/downloads/file/2/v.xpi" } ] } }
        """.utf8)
        let listed = try FirefoxAddons.listing(fromJSON: json)
        #expect(listed.version == "2.0")
        #expect(listed.sha256 == nil)
    }

    @Test func anInsecureOrIncompleteListingIsRefused() {
        let insecure = Data("""
        { "current_version": { "version": "1.0",
          "file": { "url": "http://addons.mozilla.org/firefox/downloads/file/3/w.xpi" } } }
        """.utf8)
        #expect(throws: FirefoxAddons.InstallError.self) {
            _ = try FirefoxAddons.listing(fromJSON: insecure)
        }

        let versionless = Data(#"{ "current_version": { "file": { "url": "https://a.org/x.xpi" } } }"#.utf8)
        #expect(throws: FirefoxAddons.InstallError.self) {
            _ = try FirefoxAddons.listing(fromJSON: versionless)
        }
    }

    // MARK: - The checksum

    @Test func theChecksumMustMatchTheDownload() {
        let package = Data("payload".utf8)
        let good = "239f59ed55e737c77147cf55ad0c1b030b6d7ee748a7426952f9b852d5a935e5"
        #expect(FirefoxAddons.matches(package, sha256: good))
        #expect(!FirefoxAddons.matches(package, sha256: String(good.reversed())))
        #expect(FirefoxAddons.matches(package, sha256: nil), "no checksum means nothing to contradict")
    }

    // MARK: - The library remembers the store

    @Test func aRecordWithoutASourceReadsAsChrome() throws {
        let json = Data("""
        { "id": "abc", "displayName": "Old", "version": "1", "enabled": true,
          "installedAt": 700000000 }
        """.utf8)
        let record = try JSONDecoder().decode(InstalledExtension.self, from: json)
        #expect(record.source == .chrome)
    }

    @Test func aFirefoxRecordSurvivesTheRoundTrip() throws {
        let record = InstalledExtension(
            id: "ublock-origin",
            displayName: "uBlock Origin",
            version: "1.63.2",
            enabled: true,
            installedAt: Date(timeIntervalSinceReferenceDate: 0),
            source: .firefox
        )
        let revived = try JSONDecoder().decode(
            InstalledExtension.self,
            from: JSONEncoder().encode(record)
        )
        #expect(revived.source == .firefox)
    }
}
