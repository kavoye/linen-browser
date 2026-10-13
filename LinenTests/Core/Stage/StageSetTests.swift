// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

#if DEBUG
import Foundation
import Testing

@testable import Linen

struct StageSetTests {
    private var everySite: [StageSet.Site] {
        StageSet.pinned
            + StageSet.loose
            + StageSet.reading.sites
            + StageSet.shipping.sites
            + StageSet.history.map(\.site)
            + [StageSet.opening, StageSet.video]
    }

    @Test func everyStagedAddressParses() {
        for site in everySite {
            #expect(site.url != nil, "\(site.title): \(site.address)")
        }
    }

    @Test func everyStagedAddressIsAWebsiteOverHTTPS() {
        for site in everySite {
            #expect(site.url?.scheme == "https", "\(site.title): \(site.address)")
            #expect(site.url?.host() != nil, "\(site.title): \(site.address)")
        }
    }

    @Test func noStagedSiteIsNameless() {
        for site in everySite {
            #expect(!site.title.trimmingCharacters(in: .whitespaces).isEmpty, "\(site.address)")
        }
    }

    // MARK: - The sidebar

    @Test func noListRepeatsASiteWithinItself() {
        for list in [StageSet.pinned, StageSet.loose, StageSet.reading.sites, StageSet.shipping.sites] {
            let addresses = list.map(\.address)
            #expect(addresses.count == Set(addresses).count)
        }
    }

    @Test func theSidebarHasEnoughRowsToBeWorthPhotographing() {
        #expect(StageSet.pinned.count >= 2)
        #expect(StageSet.loose.count >= 3)
        #expect(StageSet.reading.sites.count >= 2)
        #expect(StageSet.shipping.sites.count >= 2)
    }

    @Test func theTwoFoldersAreToldApartByNameAndColor() {
        #expect(StageSet.reading.name != StageSet.shipping.name)
        #expect(StageSet.reading.color != StageSet.shipping.color)
        #expect(!StageSet.reading.name.isEmpty)
        #expect(!StageSet.shipping.name.isEmpty)
    }

    @Test func theOpeningTabAndTheVideoAreBothInTheSidebar() {
        #expect(StageSet.loose.contains { $0.address == StageSet.opening.address })
        #expect(StageSet.loose.contains { $0.address == StageSet.video.address })
    }

    @Test func theStagedVideoIsAMediaFileRatherThanAPage() {
        #expect(StageSet.video.address.hasSuffix(".webm"))
    }

    // MARK: - History

    @Test func historyReadsFromMostRecentToOldest() {
        let hours = StageSet.history.map(\.hoursAgo)
        #expect(hours == hours.sorted())
    }

    @Test func everyPastVisitIsInThePastAndHappenedAtLeastOnce() {
        for visit in StageSet.history {
            #expect(visit.hoursAgo > 0, "\(visit.site.title)")
            #expect(visit.visitCount >= 1, "\(visit.site.title)")
        }
    }

    @Test func historyReachesBackMoreThanADay() {
        #expect(StageSet.history.contains { $0.hoursAgo > 24 })
        #expect(StageSet.history.contains { $0.hoursAgo < 24 })
    }

    // MARK: - Downloads

    @Test func everyStagedDownloadHasANameAHostAndASize() {
        for download in StageSet.downloads {
            #expect(!download.filename.isEmpty)
            #expect(!download.host.isEmpty)
            #expect(download.bytes > 0, "\(download.filename)")
        }
    }

    @Test func theDownloadsShowBothAFinishedAndAnUnfinishedRow() {
        #expect(StageSet.downloads.contains { $0.finished })
        #expect(StageSet.downloads.contains { !$0.finished })
    }
}

@MainActor
struct StageSeedResetTests {
    @Test func closingEveryTabAlsoClearsTheFolders() {
        let model = BrowserModel(database: .temporary())
        let tab = model.newTab(url: URL(string: "https://example.com/"))
        model.createFolder(named: "Reading", containing: [.tab(tab.id)])

        model.closeAllTabs()

        #expect(model.tabs.isEmpty)
        #expect(model.folders.isEmpty)
    }

    @Test func stagingTheDownloadsTwiceLeavesOneCopy() {
        let downloads = DownloadManager()

        downloads.stage(StageSet.downloads)
        let first = downloads.items.count
        downloads.stage(StageSet.downloads)

        #expect(first == StageSet.downloads.count)
        #expect(downloads.items.count == StageSet.downloads.count)
    }
}

#endif
