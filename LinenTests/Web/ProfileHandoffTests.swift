// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.boundedWebViews)
struct ProfileHandoffTests {
    private func makePermissions() -> SitePermissions {
        SitePermissions(
            storageURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("ProfileHandoffPermissions-\(UUID().uuidString).json")
        )
    }

    private func makeModel(_ database: AppDatabase) -> BrowserModel {
        BrowserModel(database: database, sitePermissions: makePermissions())
    }

    @Test func closingATabSilencesIt() {
        let model = makeModel(.temporary())
        let tab = model.newTab()

        model.close(tab)

        #expect(tab.isClosed)
        #expect(tab.onNavigationFinished == nil)
        #expect(tab.onDownload == nil)
        #expect(tab.webView.navigationDelegate == nil)
        #expect(tab.webView.uiDelegate == nil)
    }

    @Test func aClosedTabIgnoresItsContentProcessDying() {
        let model = makeModel(.temporary())
        let tab = model.newTab()
        var deaths = 0
        tab.onContentProcessTerminated = { deaths += 1 }

        tab.contentProcessDidTerminate()
        #expect(deaths == 1)

        model.close(tab)
        tab.contentProcessDidTerminate()
        #expect(deaths == 1)
    }

    @Test func aTabLeftOverFromTheLastProfileWritesNoHistory() {
        let model = makeModel(.temporary())
        let tab = model.newTab()
        tab.urlString = "https://example.com/"
        tab.title = "Example"
        let reportFinished = tab.onNavigationFinished
        #expect(reportFinished != nil)

        model.closeAllTabs()
        model.adopt(database: .temporary(), sitePermissions: makePermissions())

        reportFinished?(false)

        #expect(model.history.entries.isEmpty)
        #expect(model.history.count == 0)
    }

    @Test func endingPrivateBrowsingTakesItsDownloadsWithIt() {
        let downloads = DownloadManager()
        downloads.beginItem(source: URL(string: "https://example.com/report.pdf"), privately: false)
        downloads.beginItem(source: URL(string: "https://example.com/secret.pdf"), privately: true)
        #expect(downloads.items.count == 2)

        downloads.forgetPrivateDownloads()

        #expect(downloads.items.map(\.filename) == ["report.pdf"])
    }

    @Test func aTabInAPrivateProfileMarksItsDownloadsPrivate() {
        let model = makeModel(.temporary())
        model.adopt(database: .temporary(), sitePermissions: makePermissions(), privately: true)
        let tab = model.newTab()

        #expect(tab.isPrivate)
        model.downloads.beginItem(
            source: URL(string: "https://example.com/secret.pdf"),
            sourceTabID: tab.id,
            privately: tab.isPrivate
        )
        model.downloads.forgetPrivateDownloads()

        #expect(model.downloads.items.isEmpty)
    }

    @Test func theResearchGlimpseDoesNotFollowYouIntoTheNextProfile() {
        let preview = ResearchPreview()
        preview.begin(inSpace: UUID())
        #expect(preview.isLive)

        preview.forget()

        #expect(!preview.isLive)
        #expect(preview.snapshot == nil)
        #expect(preview.host == nil)
        #expect(preview.spaceID == nil)
    }

    @Test func aLiveTabStillWritesHistory() {
        let model = makeModel(.temporary())
        let tab = model.newTab()
        tab.urlString = "https://example.com/"
        tab.title = "Example"

        tab.onNavigationFinished?(false)

        #expect(model.history.entries.map(\.url) == ["https://example.com/"])
    }
}
