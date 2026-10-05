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

    @Test func profileDownloadListsStayIndependent() {
        let firstProfile = Profile(id: UUID(), name: "Work", symbol: "person", color: .gray)
        let secondProfile = Profile(id: UUID(), name: "Personal", symbol: "person", color: .gray)
        #expect(firstProfile.downloadsFile != secondProfile.downloadsFile)
        #expect(Profile.original().downloadsFile == AppDatabase.supportDirectory.appendingPathComponent("Downloads.json"))
        let firstFile = scratchFile()
        let secondFile = scratchFile()
        defer {
            try? FileManager.default.removeItem(at: firstFile)
            try? FileManager.default.removeItem(at: secondFile)
        }
        let first = DownloadManager(file: firstFile)
        let second = DownloadManager(file: secondFile)
        _ = first.beginItem(source: URL(string: "https://work.example/report.pdf"))
        _ = second.beginItem(source: URL(string: "https://personal.example/photo.jpg"))
        first.writeNow()
        second.writeNow()

        #expect(DownloadManager(file: firstFile).items.map(\.filename) == ["report.pdf"])
        #expect(DownloadManager(file: secondFile).items.map(\.filename) == ["photo.jpg"])
    }

    @Test func privateDownloadsNeitherReadNorChangePersistentHistory() throws {
        let file = scratchFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let regular = DownloadManager(file: file)
        _ = regular.beginItem(source: URL(string: "https://regular.example/report.pdf"))
        regular.writeNow()
        let saved = try Data(contentsOf: file)
        let privateDownloads = DownloadManager(file: file, persists: false)
        #expect(privateDownloads.items.isEmpty)
        let id = privateDownloads.beginItem(source: URL(string: "https://private.example/file.pdf"), privately: true)
        privateDownloads.writeNow()
        privateDownloads.forgetPrivateDownloads()
        // A cancellation callback can arrive after the window releases its downloads.
        privateDownloads.noteCancellation(id, resumeData: Data([1, 2, 3]))

        #expect(privateDownloads.items.isEmpty)
        #expect(!privateDownloads.holdsResumeState(for: id))
        #expect(try Data(contentsOf: file) == saved)
        #expect(DownloadManager(file: file).items.map(\.filename) == ["report.pdf"])
    }

    @Test func aFinishedListComesBackAfterARelaunch() {
        let file = scratchFile()
        defer { try? FileManager.default.removeItem(at: file) }

        let downloads = DownloadManager(file: file)
        let tabID = UUID()
        let id = downloads.beginItem(source: URL(string: "https://example.com/report.pdf"), sourceTabID: tabID)
        downloads.noteCancelRequested(id)
        downloads.noteCancellation(id, resumeData: nil)
        downloads.writeNow()

        let relaunched = DownloadManager(file: file)

        #expect(relaunched.items.count == 1)
        #expect(relaunched.items.first?.filename == "report.pdf")
        #expect(relaunched.items.first?.source == "example.com")
        #expect(relaunched.items.first?.sourceOrigin == "https://example.com")
        #expect(relaunched.items.first?.sourceTabID == tabID)
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
