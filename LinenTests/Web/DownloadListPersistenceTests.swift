// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// The download list outlives a quit, so what you fetched last night is still
/// there this morning and nothing but you empties it.
@MainActor
struct DownloadListPersistenceTests {
    private func scratchFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("linen-downloads-\(UUID().uuidString).json")
    }

    @Test func aFinishedListComesBackAfterARelaunch() {
        let file = scratchFile()
        defer { try? FileManager.default.removeItem(at: file) }

        let downloads = DownloadManager(file: file)
        let id = downloads.beginItem(source: URL(string: "https://example.com/report.pdf"))
        downloads.noteCancelRequested(id)
        downloads.noteCancellation(id, resumeData: nil)
        downloads.writeNow()

        let relaunched = DownloadManager(file: file)

        #expect(relaunched.items.count == 1)
        #expect(relaunched.items.first?.filename == "report.pdf")
        #expect(relaunched.items.first?.source == "example.com")
        #expect(relaunched.items.first?.state == .cancelled)
    }

    @Test func aDownloadCaughtByTheQuitSaysSo() {
        let file = scratchFile()
        defer { try? FileManager.default.removeItem(at: file) }

        let downloads = DownloadManager(file: file)
        downloads.beginItem(source: URL(string: "https://example.com/big.zip"))
        downloads.writeNow()

        let relaunched = DownloadManager(file: file)

        #expect(relaunched.items.count == 1)
        #expect(relaunched.items.first?.isRunning == false)
        if case .interrupted = relaunched.items.first?.state {
        } else {
            Issue.record("a download that was still running is not marked interrupted")
        }
    }

    @Test func aFailureKeepsItsReason() {
        let file = scratchFile()
        defer { try? FileManager.default.removeItem(at: file) }

        let downloads = DownloadManager(file: file)
        let id = downloads.beginItem(source: URL(string: "https://example.com/report.pdf"))
        downloads.noteFailure(id, reason: "The server hung up", resumeData: nil)
        downloads.writeNow()

        let relaunched = DownloadManager(file: file)

        #expect(relaunched.items.first?.state == .failed("The server hung up"))
    }

    @Test func aPrivateDownloadIsNeverWritten() {
        let file = scratchFile()
        defer { try? FileManager.default.removeItem(at: file) }

        let downloads = DownloadManager(file: file)
        let id = downloads.beginItem(source: URL(string: "https://example.com/secret.pdf"), privately: true)
        downloads.noteCancelRequested(id)
        downloads.noteCancellation(id, resumeData: nil)
        downloads.writeNow()

        let relaunched = DownloadManager(file: file)

        #expect(relaunched.items.isEmpty)
    }

    @Test func clearingTheListClearsWhatIsOnDisk() {
        let file = scratchFile()
        defer { try? FileManager.default.removeItem(at: file) }

        let downloads = DownloadManager(file: file)
        let id = downloads.beginItem(source: URL(string: "https://example.com/report.pdf"))
        downloads.noteCancelRequested(id)
        downloads.noteCancellation(id, resumeData: nil)
        downloads.writeNow()

        downloads.clearFinished()
        downloads.writeNow()

        #expect(DownloadManager(file: file).items.isEmpty)
    }

    @Test func aListWrittenByANewerBuildIsIgnoredRatherThanFatal() {
        let file = scratchFile()
        defer { try? FileManager.default.removeItem(at: file) }
        try? Data("not the list you are looking for".utf8).write(to: file)

        #expect(DownloadManager(file: file).items.isEmpty)
    }
}

/// What the list keeps is the user's choice, not a number the browser picked.
@MainActor
struct DownloadRetentionTests {
    private func managerWithOneFinishedItem() -> DownloadManager {
        let downloads = DownloadManager(file: nil)
        let id = downloads.beginItem(source: URL(string: "https://example.com/report.pdf"))
        downloads.noteCancelRequested(id)
        downloads.noteCancellation(id, resumeData: nil)
        return downloads
    }

    @Test func manuallyKeepsEverything() {
        let downloads = managerWithOneFinishedItem()
        downloads.apply(.manually, now: Date().addingTimeInterval(86_400 * 30))

        #expect(downloads.items.count == 1)
    }

    @Test func afterOneDayDropsWhatIsOlderThanADay() {
        let downloads = managerWithOneFinishedItem()
        downloads.apply(.afterOneDay, now: Date().addingTimeInterval(86_400 + 60))

        #expect(downloads.items.isEmpty)
    }

    @Test func afterOneDayKeepsWhatIsYoungerThanADay() {
        let downloads = managerWithOneFinishedItem()
        downloads.apply(.afterOneDay, now: Date().addingTimeInterval(3_600))

        #expect(downloads.items.count == 1)
    }

    @Test func aRunningDownloadIsNeverSweptAway() {
        let downloads = DownloadManager(file: nil)
        downloads.beginItem(source: URL(string: "https://example.com/big.zip"))
        downloads.apply(.afterOneDay, now: Date().addingTimeInterval(86_400 * 7))

        #expect(downloads.items.count == 1)
    }

    @Test func quittingClearsTheListOnlyWhenThatIsTheChoice() {
        let downloads = DownloadManager(file: nil)
        let id = downloads.beginItem(source: URL(string: "https://example.com/report.pdf"))
        downloads.noteCancelRequested(id)
        downloads.noteCancellation(id, resumeData: nil)

        downloads.clearOnQuitIfNeeded(.manually)
        #expect(downloads.items.count == 1)

        downloads.clearOnQuitIfNeeded(.onQuit)
        #expect(downloads.items.isEmpty)
    }
}
