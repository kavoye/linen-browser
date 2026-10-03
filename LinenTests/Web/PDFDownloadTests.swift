// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
struct PDFDownloadTests {
    private final class FrameSink: NSObject, WKScriptMessageHandler {
        var frame: WKFrameInfo?

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            frame = message.frameInfo
        }
    }

    private let source = URL(string: "https://example.com/document")!
    private let bytes = Data("PDF document with edits".utf8)

    private func directory() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func savingLoadedBytesUsesTheDownloadFolderAndRecordsCompletion() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let downloads = DownloadManager(destinationFolder: folder, asksWhereToSave: false)
        let tabID = UUID()
        var completedFilename: String?
        downloads.onFinished = { completedFilename = $0 }

        let destination = try #require(await downloads.save(
            bytes, suggestedFilename: "Report.pdf", source: source, sourceTabID: tabID
        ))
        let item = try #require(downloads.items.first)
        #expect(destination == folder.appendingPathComponent("Report.pdf"))
        #expect(try Data(contentsOf: destination) == bytes)
        #expect(item.state == .finished)
        #expect(item.sourceTabID == tabID)
        #expect(item.sourceOrigin == "https://example.com")
        #expect(item.destination == destination)
        #expect(item.bytesReceived == Int64(bytes.count))
        #expect(item.fraction == 1)
        #expect(completedFilename == "Report.pdf")
    }

    @Test func aRepeatedSaveKeepsTheExistingFile() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appendingPathComponent("Report.pdf")
        let originalBytes = Data("Original PDF".utf8)
        try originalBytes.write(to: original)
        let downloads = DownloadManager(destinationFolder: folder, asksWhereToSave: false)

        let destination = try #require(await downloads.save(bytes, suggestedFilename: "Report.pdf", source: source))
        #expect(destination.lastPathComponent == "Report 2.pdf")
        #expect(try Data(contentsOf: original) == originalBytes)
        #expect(try Data(contentsOf: destination) == bytes)
    }

    @Test func simultaneousSavesUseDifferentFilenames() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let downloads = DownloadManager(destinationFolder: folder, asksWhereToSave: false)

        async let first = downloads.save(bytes, suggestedFilename: "Report.pdf", source: source)
        async let second = downloads.save(bytes, suggestedFilename: "Report.pdf", source: source)
        let destinations = await [first, second]
        #expect(Set(destinations.compactMap { $0?.lastPathComponent }) == ["Report.pdf", "Report 2.pdf"])
        #expect(downloads.items.allSatisfy { $0.state == .finished })
    }

    @Test func aChosenLocationCanReplaceAnExistingFile() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let chosen = folder.appendingPathComponent("Saved Report.pdf")
        try Data("Old PDF".utf8).write(to: chosen)
        let downloads = DownloadManager(destinationFolder: folder, asksWhereToSave: true)
        downloads.selectSaveLocation = { filename, initialFolder, _ in
            #expect(filename == "Report.pdf")
            #expect(initialFolder == folder)
            return chosen
        }

        let destination = await downloads.save(bytes, suggestedFilename: "Report.pdf", source: source)
        #expect(destination == chosen)
        #expect(try Data(contentsOf: chosen) == bytes)
        #expect(downloads.items.first?.filename == "Saved Report.pdf")
    }

    @Test func cancellingTheSavePanelDoesNotWriteOrFinish() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let downloads = DownloadManager(destinationFolder: folder, asksWhereToSave: true)
        downloads.selectSaveLocation = { _, _, _ in nil }
        var finished = false
        downloads.onFinished = { _ in finished = true }

        let destination = await downloads.save(bytes, suggestedFilename: "Report.pdf", source: source)
        #expect(destination == nil)
        #expect(downloads.items.first?.state == .cancelled)
        #expect(!finished)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test func anUnwritableDestinationRecordsFailure() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let blockedFolder = folder.appendingPathComponent("file")
        try bytes.write(to: blockedFolder)
        let downloads = DownloadManager(destinationFolder: blockedFolder, asksWhereToSave: false)

        let destination = await downloads.save(bytes, suggestedFilename: "Report.pdf", source: source)
        #expect(destination == nil)
        let item = try #require(downloads.items.first)
        guard case .failed(let reason) = item.state else {
            Issue.record("The failed save must be visible in the download list")
            return
        }
        #expect(!reason.isEmpty)
        #expect(try Data(contentsOf: blockedFolder) == bytes)
    }

    @Test func privateDocumentSavesStayOutOfPersistedHistory() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let history = folder.appendingPathComponent("Downloads.json")
        let downloads = DownloadManager(destinationFolder: folder, asksWhereToSave: false, file: history)

        let destination = await downloads.save(bytes, suggestedFilename: "Report.pdf", source: source, privately: true)
        downloads.writeNow()
        #expect(destination != nil)
        #expect(downloads.items.first?.isPrivate == true)
        #expect(DownloadManager(file: history).items.isEmpty)
    }

    @Test(.boundedWebViews) func thePDFSaveDelegateRoutesLoadedBytesToDownloads() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let downloads = DownloadManager(destinationFolder: folder, asksWhereToSave: false)
        let model = BrowserModel(database: .temporary(), downloads: downloads)
        let tab = model.newTab()
        defer { model.close(tab) }
        let delegate = try #require(tab.webView.uiDelegate as? TabNavigationDelegate)
        #expect(delegate.responds(to: NSSelectorFromString(
            "_webView:saveDataToFile:suggestedFilename:mimeType:originatingURL:"
        )))
        #expect(delegate.responds(to: NSSelectorFromString(
            "_webView:shouldAllowPDFAtURL:toOpenFromFrame:completionHandler:"
        )))

        delegate.webView(
            tab.webView, saveDataToFile: bytes, suggestedFilename: "Report.pdf",
            mimeType: "application/pdf", originatingURL: source
        )

        #expect(await waitUntil { downloads.items.first?.state == .finished })
        let item = try #require(downloads.items.first)
        #expect(item.sourceTabID == tab.id)
        #expect(try Data(contentsOf: #require(item.destination)) == bytes)
    }

    @Test(.boundedWebViews) func previewSavesTheTemporaryCopyWithTheOriginalFilename() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let temporaryCopy = folder.appendingPathComponent("WebKit-temporary-Report.pdf")
        try bytes.write(to: temporaryCopy)
        let downloads = DownloadManager(destinationFolder: folder, asksWhereToSave: false)
        let tab = BrowserTab(opensBlank: false)
        defer { tab.detach() }
        let server = try await HTTPFixtureServer.start(routes: [
            "/document": .html("<script>window.webkit.messageHandlers.pdfTestFrame.postMessage(null)</script>"),
        ])
        defer { withExtendedLifetime(server) {} }
        let documentURL = try server.url("/document")
        let sink = FrameSink()
        let controller = tab.webView.configuration.userContentController
        controller.add(sink, name: "pdfTestFrame")
        defer { controller.removeScriptMessageHandler(forName: "pdfTestFrame") }
        tab.load(documentURL)
        #expect(await waitUntil { sink.frame != nil && !tab.webView.isLoading })
        let frame = try #require(sink.frame)
        let response = try #require(HTTPURLResponse(
            url: documentURL, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/pdf", "Content-Disposition": "inline; filename=\"Report.pdf\""]
        ))
        tab.noteMainFrameResponse(response)
        var savedForPreview = false
        tab.onSaveDocument = { data, filename, source, opensAfterSaving in
            #expect(source == documentURL)
            #expect(data == self.bytes)
            #expect(opensAfterSaving)
            let destination = await downloads.save(data, suggestedFilename: filename, source: source)
            savedForPreview = destination != nil
        }
        let delegate = try #require(tab.webView.uiDelegate as? TabNavigationDelegate)
        var decisions: [Bool] = []
        delegate.webView(tab.webView, shouldAllowPDFAtURL: temporaryCopy, toOpenFromFrame: frame) {
            decisions.append($0)
        }

        #expect(decisions == [false])
        #expect(await waitUntil { savedForPreview })
        let destination = try #require(downloads.items.first?.destination)
        #expect(destination == folder.appendingPathComponent("Report.pdf"))
        #expect(try Data(contentsOf: destination) == bytes)
    }
}
