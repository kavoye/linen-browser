// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Synchronization
import Testing
import WebKit

@testable import Linen

@MainActor
struct FaviconLoaderTests {
    // MARK: - The declared-icon answer

    /// The requested host comes from `webView.url`, which mid-navigation
    /// already names the destination while the document still belongs to the
    /// page being left. An answer from the wrong document must be refused, or
    /// the old page's icon gets filed - on disk - under the new page's host.
    @Test func declaredAnswerFromAnotherDocumentIsRefused() {
        let url = FaviconLoader.declaredIconURL(
            fromAnswer: #"{"host":"www.google.com","href":"https://www.google.com/favicon.ico"}"#,
            requestedHost: "example.com",
            pageURL: URL(string: "https://example.com/page")!
        )
        #expect(url == nil)
    }

    @Test func declaredAnswerFromTheAskedDocumentIsAccepted() {
        let url = FaviconLoader.declaredIconURL(
            fromAnswer: #"{"host":"Example.COM","href":"/icons/site.png"}"#,
            requestedHost: "example.com",
            pageURL: URL(string: "https://example.com/deep/page")!
        )
        #expect(url?.absoluteString == "https://example.com/icons/site.png")
    }

    @Test func declaredAnswerWithoutAnIconIsNothing() {
        let page = URL(string: "https://example.com/")!
        #expect(FaviconLoader.declaredIconURL(
            fromAnswer: #"{"host":"example.com","href":""}"#,
            requestedHost: "example.com",
            pageURL: page
        ) == nil)
        #expect(FaviconLoader.declaredIconURL(
            fromAnswer: "not json",
            requestedHost: "example.com",
            pageURL: page
        ) == nil)
    }

    /// github.com serves its dark icon only as SVG. `NSBitmapImageRep(data:)`
    /// answers nil for vector data, so the emptiness check threw the icon away
    /// and the row fell back to the black `/favicon.ico`.
    @Test func aVectorIconIsAnImage() throws {
        let svg = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">\
        <rect width="16" height="16" fill="white"/></svg>
        """.utf8)
        #expect(FaviconLoader.carriesAnImage(svg))
    }

    @Test func anEmptyVectorIconIsNotAnImage() throws {
        let svg = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16"></svg>
        """.utf8)
        #expect(!FaviconLoader.carriesAnImage(svg))
    }

    @Test func aVectorIconReachesTheCache() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let svg = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">\
        <rect width="16" height="16" fill="white"/></svg>
        """.utf8)

        let loader = FaviconLoader(cacheDirectory: directory)
        #expect(loader.store(svg, forHost: "example.com") != nil)

        let reopened = FaviconLoader(cacheDirectory: directory)
        #expect(reopened.cached(for: "example.com") != nil)
    }

    /// A page that rewrites its icon link has to be able to overrule what is
    /// already filed, memory and disk both, or the first answer is permanent.
    @Test func forgettingAHostClearsBothCopies() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let loader = FaviconLoader(cacheDirectory: directory)
        #expect(loader.store(try iconData(), forHost: "example.com") != nil)
        #expect(loader.cached(for: "example.com") != nil)

        loader.forget(host: "example.com")
        #expect(loader.cached(for: "example.com") == nil)

        let reopened = FaviconLoader(cacheDirectory: directory)
        #expect(reopened.cached(for: "example.com") == nil)
    }

    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("linen-favicons-\(UUID().uuidString)", isDirectory: true)
    }

    private func iconData() throws -> Data {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 16, height: 16).fill()
        image.unlockFocus()
        return try #require(image.tiffRepresentation)
    }

    @Test func cachedIconSurvivesANewLoader() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = FaviconLoader(cacheDirectory: directory)
        #expect(first.store(try iconData(), forHost: "Example.COM") != nil)

        let reopened = FaviconLoader(cacheDirectory: directory)
        #expect(reopened.cached(for: "example.com") != nil)
    }

    /// Keying on the host alone filed whichever variant resolved first against
    /// every later lookup, so a dark window kept the light site's black mark.
    @Test func eachColourSchemeKeepsItsOwnIcon() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let loader = FaviconLoader(cacheDirectory: directory)
        loader.schemeOverride = .light
        #expect(loader.store(try iconData(), forHost: "example.com") != nil)
        #expect(loader.cached(for: "example.com") != nil)

        loader.schemeOverride = .dark
        #expect(loader.cached(for: "example.com") == nil)

        #expect(loader.store(try iconData(), forHost: "example.com") != nil)
        #expect(loader.cached(for: "example.com") != nil)

        loader.schemeOverride = .light
        #expect(loader.cached(for: "example.com") != nil)
    }

    /// The dark variant has to survive a relaunch too, or every launch in dark
    /// mode refetches every icon.
    @Test func aDarkIconSurvivesANewLoader() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = FaviconLoader(cacheDirectory: directory)
        first.schemeOverride = .dark
        #expect(first.store(try iconData(), forHost: "Example.COM") != nil)

        let reopened = FaviconLoader(cacheDirectory: directory)
        reopened.schemeOverride = .dark
        #expect(reopened.cached(for: "example.com") != nil)

        reopened.schemeOverride = .light
        #expect(reopened.cached(for: "example.com") == nil)
    }

    @Test func clearingCachedFilesRemovesThePersistentCopy() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = FaviconLoader(cacheDirectory: directory)
        #expect(first.store(try iconData(), forHost: "example.com") != nil)
        first.clear(modifiedSince: .distantPast)

        let reopened = FaviconLoader(cacheDirectory: directory)
        #expect(reopened.cached(for: "example.com") == nil)
    }

    /// Restoring a session reopens every tab at once. Two of them on the same
    /// site used to race: the second found the first one's fetch in flight,
    /// gave up, and kept a globe for an icon the loader was about to have.
    @Test func concurrentLoadsForOneHostShareASingleFetch() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let stub = StubIconProtocol.fixture(payload: try iconData(), held: true)
        defer { stub.close() }

        let loader = FaviconLoader(cacheDirectory: directory, session: stub.session)
        async let first = loader.load(forHost: "example.com")
        async let second = loader.load(forHost: "example.com")

        try #require(await stub.responses.waitForRequest())
        #expect(stub.responses.requestCount == 1)
        stub.responses.open()
        let firstIcon = await first
        let secondIcon = await second
        #expect(firstIcon != nil)
        #expect(secondIcon != nil)
        #expect(stub.responses.requestCount == 1)
    }

    @Test func invalidImageDataIsNotCached() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let loader = FaviconLoader(cacheDirectory: directory)
        #expect(loader.store(Data("not an image".utf8), forHost: "example.com") == nil)
        #expect(loader.cached(for: "example.com") == nil)
    }

    // MARK: - Icons that are not icons

    private func flatData(_ colour: NSColor, side: CGFloat = 16) throws -> Data {
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        colour.setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
        image.unlockFocus()
        return try #require(image.tiffRepresentation)
    }

    /// nasa.gov serves a 16x16 `/favicon.ico` whose every pixel is transparent,
    /// and declares real PNGs in the document. It decodes as a valid image, so
    /// nothing upstream refuses it, and the row ends up wearing an empty square
    /// rather than the globe that says the site has no icon.
    @Test func anEmptyIconIsNotAnIcon() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let loader = FaviconLoader(cacheDirectory: directory)

        let blank = NSImage(size: NSSize(width: 16, height: 16))
        blank.lockFocus()
        blank.unlockFocus()
        let data = try #require(blank.tiffRepresentation)

        #expect(NSImage(data: data)?.isValid == true)
        #expect(loader.store(data, forHost: "nasa.gov") == nil)
        #expect(loader.cached(for: "nasa.gov") == nil)
    }

    /// Only emptiness is refused. Plenty of sites ship a plain coloured square,
    /// and the navigation fixtures below are drawn that way too.
    @Test func aFlatColouredIconIsKept() throws {
        #expect(FaviconLoader.carriesAnImage(try flatData(.black)))
        #expect(FaviconLoader.carriesAnImage(try flatData(.systemBlue)))
        #expect(FaviconLoader.carriesAnImage(try flatData(.white)))
        #expect(!FaviconLoader.carriesAnImage(Data("not an image".utf8)))
    }
}

/// The loader against a real WKWebView mid-navigation - the state the Google
/// repro lives in: search results set the tab's icon, following a result must
/// replace it, and a probe answered by the page being left must never land on
/// the page being reached.
@MainActor
@Suite(.serialized, .boundedWebViews)
struct FaviconNavigationTests {
    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("linen-favicon-nav-\(UUID().uuidString)", isDirectory: true)
    }

    private func iconData(side: CGFloat) throws -> Data {
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
        image.unlockFocus()
        return try #require(image.tiffRepresentation)
    }

    private func makeWebView() -> WKWebView {
        let configuration = WebViewPool.makeConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        return WKWebView(
            frame: NSRect(x: 0, y: 0, width: 500, height: 400),
            configuration: configuration
        )
    }

    private func localhost(_ url: URL) throws -> URL {
        var components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        components.host = "localhost"
        return try #require(components.url)
    }

    @Test func navigatingToAnotherHostFetchesThatSitesIcon() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = try await HTTPFixtureServer.start(routes: [
            "/a": .html(#"<link rel="icon" href="/icon-a.png"><h1>A</h1>"#),
            "/b": .html(#"<link rel="icon" href="/icon-b.png"><h1>B</h1>"#),
            "/icon-a.png": .bytes(try iconData(side: 16), contentType: "image/png"),
            "/icon-b.png": .bytes(try iconData(side: 24), contentType: "image/png"),
        ])
        let loader = FaviconLoader(cacheDirectory: directory)
        let webView = makeWebView()

        webView.load(URLRequest(url: try server.url("/a")))
        #expect(await PageSettle.untilIdle(webView, timeout: .seconds(30)))
        let first = await loader.load(for: webView)
        #expect(first?.size.width == 16)

        webView.load(URLRequest(url: try localhost(server.url("/b"))))
        #expect(await PageSettle.untilIdle(webView, timeout: .seconds(30)))
        let second = await loader.load(for: webView)
        #expect(second?.size.width == 24)
        #expect(loader.cached(for: "localhost")?.size.width == 24)
        #expect(loader.cached(for: "127.0.0.1")?.size.width == 16)
    }

    /// A cached guess looked like a settled answer, so nothing ever asked the
    /// document for the icon it declares.
    @Test func aGuessAnnouncesItselfSoTheRowKeepsAsking() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stub = StubIconProtocol.fixture(payload: try iconData(side: 16))
        defer { stub.close() }

        let loader = FaviconLoader(
            cacheDirectory: directory,
            session: stub.session
        )

        #expect(!loader.isGuessedIcon(for: "example.com"))
        #expect(await loader.load(forHost: "example.com")?.size.width == 16)
        #expect(loader.isGuessedIcon(for: "example.com"))

        // What the document declares settles it, and stops the asking.
        #expect(loader.store(try iconData(side: 24), forHost: "example.com") != nil)
        #expect(!loader.isGuessedIcon(for: "example.com"))
    }

    /// A guess read back from disk on the next launch is still a guess.
    @Test func aGuessIsStillAGuessAfterARelaunch() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stub = StubIconProtocol.fixture(payload: try iconData(side: 16))
        defer { stub.close() }

        let first = FaviconLoader(
            cacheDirectory: directory,
            session: stub.session
        )
        #expect(await first.load(forHost: "example.com") != nil)

        let reopened = FaviconLoader(cacheDirectory: directory)
        #expect(reopened.cached(for: "example.com") != nil)
        #expect(reopened.isGuessedIcon(for: "example.com"))
    }

    /// The nasa.gov shape: a tab restored from disk has no page to ask, so the
    /// row is dressed from `/favicon.ico`. That guess must give way to what the
    /// document declares once there is a document - and must not come back
    /// from the disk cache on the next launch either.
    @Test func aGuessedIconGivesWayToTheDeclaredOne() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = try await HTTPFixtureServer.start(routes: [
            "/page": .html(#"<link rel="icon" href="/declared.png"><h1>Page</h1>"#),
        ])
        // The guess is built as `https://<host>/favicon.ico`, with no port, so
        // it can never reach the fixture server. Both icon fetches go through
        // the stub instead; the page itself still comes from the server.
        let stub = StubIconProtocol.fixture(routes: [
            "/favicon.ico": try iconData(side: 16),
            "/declared.png": try iconData(side: 24),
        ])
        defer { stub.close() }

        let loader = FaviconLoader(
            cacheDirectory: directory,
            session: stub.session
        )
        let host = try #require(server.url("/page").host())

        // No page yet: the bare guess is all there is, and it dresses the row.
        let guessed = await loader.load(forHost: host)
        #expect(guessed?.size.width == 16)

        let webView = makeWebView()
        webView.load(URLRequest(url: try server.url("/page")))
        #expect(await PageSettle.untilIdle(webView, timeout: .seconds(30)))

        let declared = await loader.load(for: webView)
        #expect(declared?.size.width == 24)
        #expect(loader.cached(for: host)?.size.width == 24)

        let reopened = FaviconLoader(cacheDirectory: directory)
        #expect(reopened.cached(for: host)?.size.width == 24)
    }

    /// The other half of it: only a *guess* is passed over. An icon the page
    /// already answered for is the answer, and asking again on every load
    /// would put a request on the wire for every page view.
    @Test func anAnsweredIconIsNotAskedAgain() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = try await HTTPFixtureServer.start(routes: [
            "/page": .html(#"<link rel="icon" href="/declared.png"><h1>Page</h1>"#),
            "/declared.png": .bytes(try iconData(side: 24), contentType: "image/png"),
        ])
        let loader = FaviconLoader(cacheDirectory: directory)
        let host = try #require(server.url("/page").host())

        // Filed the way a loaded page files one, and deliberately not the size
        // this server declares: re-fetching would show up as 24.
        loader.store(try iconData(side: 30), forHost: host)

        let webView = makeWebView()
        webView.load(URLRequest(url: try server.url("/page")))
        #expect(await PageSettle.untilIdle(webView, timeout: .seconds(30)))
        #expect(await loader.load(for: webView)?.size.width == 30)
    }

    /// The repro itself: the probe runs while the tab has already turned
    /// toward the next host but the document on screen is still the old
    /// site's. Its answer must not be filed under the new host.
    @Test func probeAnsweredByThePageBeingLeftNeverLandsOnTheNextHost() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let response = ResponseGate()
        defer { response.open() }
        let server = try await HTTPFixtureServer.start(routes: [
            "/a": .html(#"<link rel="icon" href="/icon-a.png"><h1>A</h1>"#),
            "/icon-a.png": .bytes(try iconData(side: 16), contentType: "image/png"),
            "/b": .html(#"<link rel="icon" href="/icon-b.png"><h1>B</h1>"#, gate: response),
            "/icon-b.png": .bytes(try iconData(side: 24), contentType: "image/png"),
        ])
        let loader = FaviconLoader(cacheDirectory: directory)
        let webView = makeWebView()

        webView.load(URLRequest(url: try server.url("/a")))
        #expect(await PageSettle.untilIdle(webView, timeout: .seconds(30)))

        // The slow response holds this navigation provisional: `webView.url`
        // says localhost while the document is still A's.
        webView.load(URLRequest(url: try localhost(server.url("/b"))))
        #expect(await waitUntil { webView.url?.host() == "localhost" })
        let midNavigation = await loader.load(for: webView)
        #expect(midNavigation?.size.width != 16)
        #expect(loader.cached(for: "localhost")?.size.width != 16)

        response.open()
        #expect(await PageSettle.untilIdle(webView, timeout: .seconds(30)))
        let landed = await loader.load(for: webView)
        #expect(landed?.size.width == 24)
        #expect(loader.cached(for: "localhost")?.size.width == 24)
    }
}

private nonisolated final class StubIconProtocol: URLProtocol, @unchecked Sendable {
    struct Fixture: Sendable {
        let id: String
        let session: URLSession
        let responses: ResponseGate

        func close() {
            responses.open()
            session.invalidateAndCancel()
            StubIconProtocol.fixtures.withLock { $0[id] = nil }
        }
    }

    private struct Reply: Sendable {
        let payload: Data?
        let routes: [String: Data]
        let responses: ResponseGate
    }

    private static let header = "X-Linen-Test-Fixture"
    private static let fixtures = Mutex<[String: Reply]>([:])

    static func fixture(payload: Data? = nil, routes: [String: Data] = [:], held: Bool = false) -> Fixture {
        let id = UUID().uuidString
        let responses = ResponseGate()
        if !held {
            responses.open()
        }
        fixtures.withLock { $0[id] = Reply(payload: payload, routes: routes, responses: responses) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubIconProtocol.self]
        configuration.httpAdditionalHeaders = [header: id]
        return Fixture(id: id, session: URLSession(configuration: configuration), responses: responses)
    }

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: Self.header),
              let reply = Self.fixtures.withLock({ $0[id] }),
              let url = request.url,
              let data = reply.routes.isEmpty ? reply.payload : reply.routes[url.path()] else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        reply.responses.submit { [weak self] in
            guard let self else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
