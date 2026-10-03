// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct BrowserDocumentTitleTests {
    private func pdf() throws -> Data {
        let data = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: data))
        var bounds = CGRect(x: 0, y: 0, width: 300, height: 200)
        let context = try #require(CGContext(consumer: consumer, mediaBox: &bounds, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 20, y: 20, width: 100, height: 100))
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    @Test(arguments: ["/Quarterly%20Report.pdf", "/download", "/download#page=1"])
    func aPDFUsesItsFilenameAndKeepsItWhenGoingBack(path: String) async throws {
        let route = String(path.prefix { $0 != "#" })
        var headers = ["Content-Type": "application/pdf"]
        if route == "/download" {
            headers["Content-Disposition"] = "inline; filename=\"Quarterly Report.pdf\""
        }
        let server = try await HTTPFixtureServer.start(routes: [
            route: .init(status: "200 OK", headers: headers, body: try pdf()),
            "/untitled": .html("<!doctype html><p>Page</p>"),
        ])
        defer { withExtendedLifetime(server) {} }
        let url = try server.url(path)
        let tab = BrowserTab(opensBlank: false)

        tab.load(url)
        #expect(await settled(tab, at: url))
        #expect(tab.title == "Quarterly Report.pdf")
        #expect(!tab.isShowingStartPage)

        let website = try server.url("/untitled")
        tab.load(website)
        #expect(await settled(tab, at: website))
        #expect(tab.title == "New Page")

        tab.goBack()
        #expect(await settled(tab, at: url))
        #expect(tab.title == "Quarterly Report.pdf")
    }

    @Test func aLocalPDFUsesItsFilename() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Local Report.pdf")
        try pdf().write(to: url)
        let tab = BrowserTab(opensBlank: false)

        tab.load(url)
        #expect(await settled(tab, at: url))
        #expect(tab.title == "Local Report.pdf")
        #expect(!tab.isShowingStartPage)
    }

    @Test func aPDFKeepsItsFilenameAfterSessionRestore() async throws {
        let server = try await HTTPFixtureServer.start(routes: [
            "/download": .init(
                status: "200 OK",
                headers: [
                    "Content-Type": "application/pdf",
                    "Content-Disposition": "inline; filename=\"Restored Report.pdf\"",
                ],
                body: try pdf()
            ),
        ])
        defer { withExtendedLifetime(server) {} }
        let url = try server.url("/download")
        let database = AppDatabase.temporary()
        let model = BrowserModel(database: database)
        let tab = model.newTab(url: url)
        #expect(await settled(tab, at: url))
        #expect(tab.title == "Restored Report.pdf")
        model.saveBlocking()

        let reopened = BrowserModel(database: database)
        reopened.restoreSession()
        let restored = try #require(reopened.activeTab)
        #expect(restored.title == "Restored Report.pdf")
        #expect(await waitUntil {
            !restored.isRestoring && restored.webView.url == url && !restored.webView.isLoading
        })
        #expect(restored.title == "Restored Report.pdf")
    }
}
