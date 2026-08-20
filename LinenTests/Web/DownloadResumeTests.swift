// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// Picking a transfer back up where it stopped.
///
/// Driven through `DownloadManager`'s own state calls rather than its
/// `WKDownloadDelegate` methods: a `WKDownload` exists only because WebKit
/// made one, and none of what is interesting here is WebKit's - it is what a
/// row becomes when a transfer dies, when the user stops it, and when the two
/// answers arrive in either order.
@MainActor
@Suite(.boundedWebViews)
struct DownloadResumeTests {
    private let token = Data("resume-token".utf8)

    private func makeRunning() -> (DownloadManager, UUID) {
        let downloads = DownloadManager()
        let id = downloads.beginItem(source: URL(string: "https://example.com/big.zip"))
        return (downloads, id)
    }

    private func item(_ downloads: DownloadManager, _ id: UUID) throws -> DownloadManager.Item {
        try #require(downloads.items.first { $0.id == id })
    }

    @Test func anActiveDownloadKeepsItsSourceTabAssociation() {
        let downloads = DownloadManager()
        let tabID = UUID()
        let id = downloads.beginItem(
            source: URL(string: "https://example.com/file.zip"),
            sourceTabID: tabID
        )

        #expect(downloads.hasActiveDownload(for: tabID))
        #expect(!downloads.hasActiveDownload(for: UUID()))

        downloads.noteFailure(id, reason: "Stopped", resumeData: nil)
        #expect(!downloads.hasActiveDownload(for: tabID))
    }

    // MARK: - Failing

    /// The whole point: a dropped connection halfway through a large file used
    /// to cost the whole file.
    @Test func aFailureCarryingATokenIsInterruptedRatherThanFailed() throws {
        let (downloads, id) = makeRunning()

        downloads.noteFailure(id, reason: "The network connection was lost.", resumeData: token)

        let row = try item(downloads, id)
        #expect(row.state == .interrupted("The network connection was lost."))
        #expect(row.isResumable)
        #expect(row.stoppedReason == "The network connection was lost.")
    }

    /// Without a token there is nothing to build on, so the row must not offer
    /// a Resume that could only start the file again from nothing.
    @Test func aFailureWithoutATokenIsFailed() throws {
        let (downloads, id) = makeRunning()

        downloads.noteFailure(id, reason: "Not found.", resumeData: nil)

        let row = try item(downloads, id)
        #expect(row.state == .failed("Not found."))
        #expect(!row.isResumable)
        #expect(!downloads.canResume(row))
    }

    /// A finished or cancelled row already has a state of its own, and a late
    /// failure callback must not overwrite it.
    @Test func aFailureLeavesARowThatAlreadyStoppedAlone() throws {
        let (downloads, id) = makeRunning()

        downloads.noteCancelRequested(id)
        downloads.noteCancellation(id, resumeData: nil)
        downloads.noteFailure(id, reason: "cancelled", resumeData: nil)

        #expect(try item(downloads, id).state == .cancelled)
    }

    /// Stop has to read as stopped straight away. WebKit's answer arrives a
    /// beat later, and a row still showing a progress bar in between reads as
    /// a button that did nothing.
    @Test func stoppingReadsAsStoppedBeforeWebKitAnswers() throws {
        let (downloads, id) = makeRunning()

        downloads.noteCancelRequested(id)

        #expect(try item(downloads, id).state == .cancelled)
        #expect(downloads.activeCount == 0)
    }

    // MARK: - Cancelling

    /// Cancelling keeps received data so the row can offer Resume.
    @Test func aCancelKeepsWhatAlreadyArrived() throws {
        let (downloads, id) = makeRunning()

        downloads.noteCancelRequested(id)
        downloads.noteCancellation(id, resumeData: token)

        let row = try item(downloads, id)
        #expect(row.state == .cancelled)
        #expect(row.isResumable)
    }

    // MARK: - The two callbacks racing

    /// WebKit answers a cancel twice: once through the cancel's own completion
    /// and once through the failure callback. Either can arrive first, and
    /// only one of them carries the token - so whichever is second must read
    /// what is stored rather than trusting its own argument. Reading the
    /// argument is what threw the token away.
    @Test func theTokenSurvivesWhicheverCallbackArrivesSecond() throws {
        for order in ["failure first", "cancel first"] {
            let (downloads, id) = makeRunning()
            downloads.noteCancelRequested(id)

            if order == "failure first" {
                downloads.noteFailure(id, reason: "stopped", resumeData: token)
                downloads.noteCancellation(id, resumeData: nil)
            } else {
                downloads.noteCancellation(id, resumeData: token)
                downloads.noteFailure(id, reason: "stopped", resumeData: nil)
            }

            let row = try item(downloads, id)
            #expect(row.isResumable, "token lost with \(order)")
            downloads.webViewProvider = { nil }
            // The row still holds the token; only the missing web view stops
            // it being offered.
            #expect(!downloads.canResume(row))
        }
    }

    // MARK: - Resuming

    /// Resume needs somewhere to run the transfer from as well as a token, so
    /// the button must not appear when the browser has no web view to give it.
    @Test func resumeIsNotOfferedWithoutAWebView() throws {
        let (downloads, id) = makeRunning()
        downloads.noteFailure(id, reason: "stopped", resumeData: token)

        #expect(!downloads.canResume(try item(downloads, id)))
    }

    /// And asking anyway changes nothing, rather than half-starting a transfer
    /// that has nowhere to go.
    @Test func resumingWithoutAWebViewLeavesTheRowAlone() throws {
        let (downloads, id) = makeRunning()
        downloads.noteFailure(id, reason: "stopped", resumeData: token)

        downloads.resume(try item(downloads, id))

        let row = try item(downloads, id)
        #expect(row.state == .interrupted("stopped"))
        #expect(row.isResumable)
    }

    @Test func startingAResumePutsTheRowBackToRunning() throws {
        let (downloads, id) = makeRunning()
        downloads.noteFailure(id, reason: "stopped", resumeData: token)

        downloads.noteResumeStarted(id)

        let row = try item(downloads, id)
        #expect(row.state == .running)
        // No Resume button while it is running.
        #expect(!row.isResumable)
    }

    /// If the resumed transfer dies without a token of its own, the one from
    /// last time is still the way to try again. Clearing it on resume meant a
    /// second failure was the end of the file.
    @Test func aResumeThatFailsAgainCanStillBeResumed() throws {
        let (downloads, id) = makeRunning()
        downloads.noteFailure(id, reason: "stopped", resumeData: token)
        downloads.noteResumeStarted(id)

        downloads.noteFailure(id, reason: "stopped again", resumeData: nil)

        let row = try item(downloads, id)
        #expect(row.state == .interrupted("stopped again"))
        #expect(row.isResumable)
    }

    // MARK: - Where the bytes go

    /// WebKit appends to what is already on disk. Handing it a fresh name
    /// would leave the partial file behind and start the download over beside
    /// it, which is how a resume becomes "big.zip" and "big 2.zip".
    @Test func aResumedTransferIsGivenTheSamePathAgain() throws {
        let (downloads, id) = makeRunning()
        let path = URL(filePath: "/tmp/big.zip")
        downloads.noteDestination(path, expectedLength: 0, for: id)
        downloads.noteFailure(id, reason: "stopped", resumeData: token)
        downloads.noteResumeStarted(id)

        #expect(downloads.reusableDestination(for: id) == path)
    }

    /// Only once: the row is no longer resuming after that, and a later
    /// transfer in the same row picks its own name.
    @Test func thePathIsOnlyReusedForTheResumeThatAskedForIt() throws {
        let (downloads, id) = makeRunning()
        downloads.noteDestination(URL(filePath: "/tmp/big.zip"), expectedLength: 0, for: id)
        downloads.noteResumeStarted(id)

        #expect(downloads.reusableDestination(for: id) != nil)
        #expect(downloads.reusableDestination(for: id) == nil)
    }

    /// An ordinary transfer has no path to reuse, or every download would
    /// overwrite whatever its row last pointed at.
    @Test func anOrdinaryTransferPicksAFreshPath() throws {
        let (downloads, id) = makeRunning()
        downloads.noteDestination(URL(filePath: "/tmp/big.zip"), expectedLength: 0, for: id)

        #expect(downloads.reusableDestination(for: id) == nil)
    }

    // MARK: - Not leaking

    /// Forgetting the row forgets the token with it. Held on, these would
    /// accumulate for the life of the process, each the size of a server's
    /// resume state.
    @Test func removingAnInterruptedRowDropsItsToken() throws {
        let (downloads, id) = makeRunning()
        downloads.noteFailure(id, reason: "stopped", resumeData: token)
        let row = try item(downloads, id)

        downloads.remove(row)

        #expect(downloads.items.isEmpty)
        #expect(!downloads.holdsResumeState(for: id))
    }

    @Test func clearingTheListDropsEveryToken() throws {
        let (downloads, id) = makeRunning()
        downloads.noteFailure(id, reason: "stopped", resumeData: token)

        downloads.clearFinished()

        #expect(downloads.items.isEmpty)
        #expect(!downloads.holdsResumeState(for: id))
    }

    /// A stopped row is not a running one: Clear may take it, and the chrome
    /// must not keep showing a transfer in progress.
    @Test func anInterruptedRowIsNotRunning() throws {
        let (downloads, id) = makeRunning()
        #expect(downloads.activeCount == 1)

        downloads.noteFailure(id, reason: "stopped", resumeData: token)

        #expect(downloads.activeCount == 0)
        #expect(!(try item(downloads, id).isRunning))
    }

    // MARK: - What the row says

    /// How far it got, because that is what Resume is about to build on.
    @Test func aStoppedRowSaysHowFarItGot() throws {
        let (downloads, id) = makeRunning()
        downloads.noteProgress(received: 3_000_000, expected: 18_000_000, for: id)
        downloads.noteFailure(id, reason: "The network connection was lost.", resumeData: token)

        let summary = try item(downloads, id).sizeSummary
        #expect(summary.contains("3"))
        #expect(summary.contains("18"))
    }

    /// A server that declared no size still gets a sentence rather than "of 0".
    @Test func aStoppedRowWithNoDeclaredSizeStillReads() throws {
        let (downloads, id) = makeRunning()
        downloads.noteProgress(received: 3_000_000, expected: 0, for: id)
        downloads.noteFailure(id, reason: "stopped", resumeData: token)

        let summary = try item(downloads, id).sizeSummary
        #expect(summary.contains("3"))
        #expect(!summary.contains("0 bytes"))
    }
}
