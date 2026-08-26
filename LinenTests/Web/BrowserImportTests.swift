// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

/// The importer against the file every browser exports: one Netscape bookmark
/// file. The fixtures below are trimmed copies of real exports - Safari's,
/// Chrome's and Firefox's - because the markup is the part reading code can't
/// check.
@MainActor
struct BrowserImportTests {
    private static let chromeExport = """
    <!DOCTYPE NETSCAPE-Bookmark-file-1>
    <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
    <TITLE>Bookmarks</TITLE>
    <H1>Bookmarks</H1>
    <DL><p>
        <DT><H3 ADD_DATE="1724198400" PERSONAL_TOOLBAR_FOLDER="true">Bookmarks bar</H3>
        <DL><p>
            <DT><A HREF="https://example.com/" ADD_DATE="1724198400" ICON="data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==">Example</A>
            <DT><H3 ADD_DATE="1724198400">Work</H3>
            <DL><p>
                <DT><A HREF="https://docs.example.com/" ADD_DATE="1724198401">Docs &amp; Notes</A>
            </DL><p>
        </DL><p>
        <DT><A HREF="https://deep.example.com/">Deep</A>
    </DL><p>
    """

    private static let safariExport = """
    <!DOCTYPE NETSCAPE-Bookmark-file-1>
    <HTML>
    <HEAD><Title>Bookmarks</Title></HEAD>
    <BODY>
    <H1>Bookmarks</H1>
    <DL>
        <DT><H3 FOLDED>Favorites</H3>
        <DL>
            <DT><A HREF="https://apple.com/">Apple</A>
            <DT><A HREF="https://example.com/?a=1&amp;b=2">It&#39;s a Test</A>
        </DL>
    </DL>
    </BODY></HTML>
    """

    // MARK: - Reading the file

    @Test func linksComeOutOfEveryNestedFolder() {
        let marks = BrowserImport.bookmarks(inHTML: Self.chromeExport)

        #expect(marks.map(\.url) == [
            "https://example.com/", "https://docs.example.com/", "https://deep.example.com/",
        ])
        #expect(marks.first?.title == "Example")
        // Folder names are not bookmarks; the H3 rows must not become tabs.
        #expect(!marks.map(\.title).contains("Work"))
    }

    @Test func safariUsesTheSameFormat() {
        let marks = BrowserImport.bookmarks(inHTML: Self.safariExport)

        #expect(marks.map(\.url) == ["https://apple.com/", "https://example.com/?a=1&b=2"])
        #expect(marks.last?.title == "It's a Test")
    }

    /// Titles and addresses are HTML-escaped in the file. An ampersand in a
    /// query string is `&amp;`, and every browser writes apostrophes and
    /// dashes as numeric references.
    @Test func escapedTextIsDecoded() {
        #expect(BrowserImport.entities(in: "Rock &amp; Roll") == "Rock & Roll")
        #expect(BrowserImport.entities(in: "&lt;tag&gt; &quot;quoted&quot;") == "<tag> \"quoted\"")
        #expect(BrowserImport.entities(in: "It&#39;s &#x2014; here") == "It's — here")
        // A bare ampersand is left alone rather than eating what follows it.
        #expect(BrowserImport.entities(in: "Q & A") == "Q & A")
    }

    @Test func onlyWebPagesArrive() {
        let html = """
        <DT><A HREF="https://good.example/">Good</A>
        <DT><A HREF="javascript:void(0)">Bookmarklet</A>
        <DT><A HREF="place:type=6&amp;sort=14">Recent Tags</A>
        <DT><A HREF="file:///Users/someone/notes.html">Notes</A>
        """
        #expect(BrowserImport.bookmarks(inHTML: html).map(\.url) == ["https://good.example/"])
    }

    /// The same page saved in the toolbar and in a folder is one bookmark,
    /// not two tabs with the same address.
    @Test func aPageSavedTwiceArrivesOnce() {
        let html = """
        <DT><A HREF="https://example.com/">First</A>
        <DT><A HREF="https://example.com/">Second</A>
        """
        let marks = BrowserImport.bookmarks(inHTML: html)
        #expect(marks.count == 1)
        #expect(marks.first?.title == "First")
    }

    /// Any HTML file can be chosen in the panel. A saved web page is full of
    /// links, and none of them are bookmarks: only a file a browser exported
    /// is read.
    @Test func aSavedWebPageIsNotAnExport() {
        let page = """
        <html><body>
        <a href="https://example.com/one">One</a>
        <a href="https://example.com/two">Two</a>
        </body></html>
        """
        #expect(!BrowserImport.isExport(page))
        #expect(BrowserImport.bookmarks(inHTML: page).isEmpty)
        #expect(BrowserImport.isExport(Self.chromeExport))
        #expect(BrowserImport.isExport(Self.safariExport))
    }

    @Test func anUntitledLinkShowsItsAddress() {
        let marks = BrowserImport.bookmarks(inHTML: "<DT><A HREF=\"https://bare.example/\"></A>")
        #expect(marks.first?.title == "https://bare.example/")
    }

    @Test func addDateIsSecondsSinceNineteenSeventy() {
        let marks = BrowserImport.bookmarks(
            inHTML: "<DT><A HREF=\"https://example.com/\" ADD_DATE=\"1724198400\">Example</A>"
        )
        #expect(marks.first?.date == Date(timeIntervalSince1970: 1_724_198_400))
        #expect(BrowserImport.date(0) == .distantPast)
    }

    /// Older exports are Windows-1252, not UTF-8. Reading must not fail on
    /// a file that has one accented character in a title.
    @Test func aFileThatIsNotUTF8IsStillRead() throws {
        let latin = try #require("Café".data(using: .windowsCP1252))
        #expect(BrowserImport.decode(latin) == "Café")
    }

    @Test func readingAFileThatIsNotThereFails() {
        let missing = URL(fileURLWithPath: "/nowhere/bookmarks.html")
        #expect(throws: BrowserImport.Failure.self) { try BrowserImport.read(missing) }
    }

    @Test func readingAnExportGivesTheFolderItsName() throws {
        let file = FileManager.default.temporaryDirectory
            .appending(path: "linen-import-\(UUID().uuidString).html")
        try Data(Self.safariExport.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let payload = try BrowserImport.read(file)
        #expect(payload.bookmarks.count == 2)
        #expect(payload.folderName == BrowserImport.folderName)
        #expect(!payload.isEmpty)
    }

    /// The half the confirmation dialog reads out loud. A file with nothing
    /// in it must say so rather than offering "0 bookmarks".
    @Test func thePayloadNamesOnlyWhatItFound() {
        #expect(BrowserImport.Payload(bookmarks: []).isEmpty)
        #expect(BrowserImport.bookmarks(inHTML: "<html><body>Not a bookmarks file</body></html>").isEmpty)
        #expect(BrowserImport.Payload(bookmarks: [
            .init(url: "https://example.com/", title: "Example", date: .distantPast),
        ]).phrase == "1 bookmark")
    }

    // MARK: - Applying

    @Test(.boundedWebViews) func bookmarksBecomeOneCollapsedFolderOfColdTabs() {
        let model = BrowserModel(database: .temporary())
        let folder = model.importBookmarksFolder(named: "Imported Bookmarks", entries: [
            .init(url: "https://example.com/", title: "Example", date: .distantPast),
            .init(url: "https://docs.example.com/", title: "Docs", date: .distantPast),
            // Not a web page; a bookmarklet must not become a tab.
            .init(url: "javascript:void(0)", title: "Bookmarklet", date: .distantPast),
        ])

        #expect(folder?.name == "Imported Bookmarks")
        #expect(folder?.isExpanded == false)
        #expect(folder.map { model.tabs(in: $0).count } == 2)
        // Imported in the background: nothing steals the active tab, and
        // nothing has loaded - cold views carry no page until activated.
        #expect(model.tabs.allSatisfy { $0.webView.url == nil })
    }

    /// Reading and writing are two steps: the dialog counts a payload, and
    /// only `apply` puts anything into the browser.
    @Test func applyingAPayloadFillsTheFolder() {
        let model = BrowserModel(database: .temporary())
        let payload = BrowserImport.Payload(
            bookmarks: [.init(url: "https://saved.example/", title: "Saved", date: .distantPast)],
            folderName: "Imported Bookmarks"
        )

        #expect(model.folders.isEmpty)

        BrowserImport.apply(payload, into: model)
        #expect(model.folders.first?.name == "Imported Bookmarks")
        #expect(model.tabs.map(\.urlString) == ["https://saved.example/"])
        // Bookmarks are not visited pages: nothing lands in history.
        #expect(model.history.entries.isEmpty)
    }
}
