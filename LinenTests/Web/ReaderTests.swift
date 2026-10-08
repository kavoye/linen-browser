// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct ReaderTests {
    private static let articleURL = URL(string: "https://example.com/story")!

    private static func article(blocks: [String] = ["One.", "Two.", "Three."]) -> ReaderArticle {
        ReaderArticle(url: articleURL, title: "Headline", content: "<p>body</p>", blocks: blocks)
    }

    private static let paragraph = String(
        repeating: "The river kept its slow pace through the valley while the town woke around it. ",
        count: 6
    )

    private static let fixture = """
    <!doctype html><html lang="en"><head><title>Valley Morning - Example News</title></head><body>
    <nav><a href="/">Home</a> <a href="/world">World</a> <a href="/sport">Sport</a></nav>
    <div class="ad" id="banner">Buy now! Limited offer!</div>
    <article>
    <h1>Valley Morning</h1>
    <p class="byline">By Sam Rivers</p>
    <p onclick="alert(1)">\(paragraph)</p>
    <p>\(paragraph)<a href="javascript:alert(2)">a link</a></p>
    <script>window.stolen = true;</script>
    <p>\(paragraph)</p>
    <p>\(paragraph)</p>
    <iframe src="https://ads.example.net/frame"></iframe>
    </article>
    <footer>Copyright Example News</footer>
    </body></html>
    """

    private func loadedFixture() async -> WKWebView {
        await loaded(Self.fixture, at: Self.articleURL)
    }

    // MARK: - Extraction

    @Test func extractsTheArticleWithoutChromeOrScripts() async throws {
        let webView = await loadedFixture()

        #expect(await ReaderExtractor.isReaderable(webView))
        let article = try #require(await ReaderExtractor.article(in: webView))

        #expect(article.url == Self.articleURL)
        #expect(article.title.contains("Valley Morning"))
        #expect(article.blocks.count >= 4)
        #expect(article.text.contains("The river kept its slow pace"))
        #expect(!article.text.contains("Buy now"))
        #expect(!article.text.contains("Copyright Example News"))
        #expect(!article.content.contains("<script"))
        #expect(!article.content.contains("onclick"))
        #expect(!article.content.contains("javascript:"))
        #expect(!article.content.contains("<iframe"))
        #expect(article.content.contains("data-linen-block=\"0\""))
    }

    @Test func extractionLeavesThePageAlone() async throws {
        let webView = await loadedFixture()
        _ = try #require(await ReaderExtractor.article(in: webView))

        let banner = try await webView.evaluateJavaScript("document.getElementById('banner') !== null") as? Bool
        #expect(banner == true)
        let readability = try await webView.evaluateJavaScript("typeof Readability") as? String
        #expect(readability == "undefined")
    }

    @Test func nonWebPagesAreNeverEligible() {
        #expect(ReaderExtractor.isEligible(URL(string: "https://example.com")!))
        #expect(!ReaderExtractor.isEligible(URL(string: "linen://start")!))
        #expect(!ReaderExtractor.isEligible(URL(string: "file:///tmp/a.html")!))
        #expect(!ReaderExtractor.isEligible(URL(string: "about:blank")!))
    }

    // MARK: - Article

    @Test func decodesTheExtractorPayload() throws {
        let json = """
        {"url":"https://example.com/story","title":" Headline ","byline":"Sam","siteName":"Example",
         "excerpt":"","lang":"he","dir":"rtl","content":"<p>x</p>","blocks":["a b c"]}
        """
        let article = try #require(ReaderArticle(json: json))

        #expect(article.title == "Headline")
        #expect(article.isRightToLeft)
        #expect(article.language == "he")
        #expect(article.wordCount == 3)
        #expect(ReaderArticle(json: #"{"url":"https://example.com","content":"","blocks":[]}"#) == nil)
    }

    @Test func readingTimeNeverRoundsToZero() {
        #expect(Self.article(blocks: ["short"]).readingMinutes == 1)
        let long = Array(repeating: String(repeating: "word ", count: 230), count: 5)
        #expect(Self.article(blocks: long).readingMinutes == 5)
    }

    // MARK: - Page

    @Test func theReaderPageEscapesMetadata() {
        let article = ReaderArticle(
            url: Self.articleURL,
            title: "<img src=x onerror=alert(1)>",
            byline: "\"Sam\" & co",
            content: "<p data-linen-block=\"0\">body</p>",
            blocks: ["body"]
        )
        let html = ReaderPage.html(for: article, typeface: .serif, palette: .sepia, textSize: 19)

        #expect(!html.contains("<img src=x"))
        #expect(html.contains("&lt;img src=x onerror=alert(1)&gt;"))
        #expect(html.contains("&quot;Sam&quot; &amp; co"))
        #expect(html.contains("Content-Security-Policy"))
        #expect(html.contains("data-palette=\"sepia\""))
        #expect(html.contains("data-typeface=\"serif\""))
    }

    @Test func highlightTargetsTheTitleOrABlock() {
        #expect(ReaderPage.highlightScript(block: ReaderPage.titleBlock).contains("#linen-title"))
        #expect(ReaderPage.highlightScript(block: 3).contains("[data-linen-block=\"3\"]"))
        #expect(ReaderPage.highlightScript(block: nil).contains("const selector = '';"))
    }

    @Test func resetRestoresEveryAppearanceDefault() throws {
        let defaults = try #require(UserDefaults(suiteName: TestDefaults.name("ReaderTests")))
        let appearance = ReaderAppearance(defaults: defaults)
        #expect(appearance.isDefault)

        appearance.typeface = .charter
        appearance.palette = .sepia
        appearance.grow()
        #expect(!appearance.isDefault)

        appearance.reset()
        #expect(appearance.isDefault)
        #expect(ReaderAppearance(defaults: defaults).isDefault)
    }

    @Test func readerFollowsTheReadingEngine() {
        var systemOutputs = 0
        var assistantOutputs = 0
        let voice = ReaderVoice {
            systemOutputs += 1
            return ScriptedSpeech()
        }

        voice.speak("One")
        #expect(systemOutputs == 1)

        voice.setAssistantOutput {
            assistantOutputs += 1
            return ScriptedSpeech()
        }
        voice.speak("Two")
        voice.speak("Three")
        #expect(assistantOutputs == 1)

        voice.setAssistantOutput(nil)
        voice.speak("Four")
        #expect(systemOutputs == 2)
    }

    // MARK: - Session

    @Test func openingShowsTheArticleAndANewPageClosesIt() async {
        let session = ReaderSession()
        session.driver = ReaderDriver(probe: { true }, extract: { Self.article() })
        var deactivated = 0
        session.onDeactivate = { deactivated += 1 }

        #expect(await session.open())
        #expect(session.isActive)
        #expect(session.article == Self.article())

        session.pageChanged()
        #expect(!session.isActive)
        #expect(session.article == nil)
        #expect(session.availability == .unknown)
        #expect(deactivated == 1)
    }

    @Test func aPageWithoutAnArticleCannotOpen() async {
        let session = ReaderSession()
        session.driver = ReaderDriver(probe: { true }, extract: { nil })

        #expect(!(await session.open()))
        #expect(!session.isActive)
        #expect(session.availability == .unavailable)
        #expect(!session.isAvailable)
    }

    @Test func anExtractionThatOutlivesItsPageIsDropped() async {
        let session = ReaderSession()
        let gate = ExtractionGate()
        session.driver = ReaderDriver(probe: { true }, extract: { await gate.wait() })

        let opening = Task { await session.open() }
        await gate.untilWaiting()
        session.pageChanged()
        gate.release(Self.article())

        #expect(!(await opening.value))
        #expect(!session.isActive)
        #expect(session.article == nil)
    }

    @Test func theProbeRetriesOnceForLatePages() async {
        let session = ReaderSession()
        session.retryDelay = .zero
        var calls = 0
        session.driver = ReaderDriver(
            probe: {
                calls += 1
                return calls > 1
            },
            extract: { Self.article() }
        )

        await session.probe()

        #expect(calls == 2)
        #expect(session.availability == .available)
    }

    @Test func aSecondProbeForTheSamePageDoesNotRunAgain() async {
        let session = ReaderSession()
        session.retryDelay = .milliseconds(200)
        var calls = 0
        session.driver = ReaderDriver(
            probe: {
                calls += 1
                return false
            },
            extract: { nil }
        )

        async let first: Void = session.probe()
        async let second: Void = session.probe()
        _ = await (first, second)

        #expect(calls == 2)
        #expect(session.availability == .unavailable)
    }

    @Test func aNewPageProbesEvenWhileTheOldProbeWaits() async {
        let session = ReaderSession()
        session.retryDelay = .milliseconds(200)
        var calls = 0
        session.driver = ReaderDriver(
            probe: {
                calls += 1
                return calls > 1
            },
            extract: { Self.article() }
        )

        let old = Task { await session.probe() }
        await Task.yield()
        session.pageChanged()
        await session.probe()
        await old.value

        #expect(calls == 2)
        #expect(session.availability == .available)
    }

    @Test func contentThatArrivesAfterTheRetryIsWatchedFor() async {
        let session = ReaderSession()
        session.retryDelay = .zero
        var probes = 0
        var watches = 0
        session.driver = ReaderDriver(
            probe: {
                probes += 1
                return false
            },
            watch: {
                watches += 1
                return true
            },
            extract: { Self.article() }
        )

        await session.probe()

        #expect(probes == 2)
        #expect(watches == 1)
        #expect(session.availability == .available)
    }

    @Test func onlyTheFrontmostTabProbes() async {
        let browser = BrowserModel(database: .temporary())
        let front = browser.newTab()
        let back = browser.newTab()
        browser.activate(front)
        var probes: [UUID] = []
        for tab in [front, back] {
            let id = tab.id
            tab.reader.driver = ReaderDriver(
                probe: {
                    probes.append(id)
                    return true
                },
                extract: { Self.article() }
            )
        }
        let page = Self.fixture
        for tab in [front, back] {
            tab.webView.loadHTMLString(page, baseURL: Self.articleURL)
            #expect(await PageSettle.untilIdle(tab.webView, timeout: .seconds(30)))
        }
        #expect(await eventually { front.reader.availability == .available })

        #expect(front.isFrontmost)
        #expect(!back.isFrontmost)
        #expect(!probes.contains(back.id))
        #expect(back.reader.availability == .unknown)

        browser.activate(back)

        #expect(await eventually { back.reader.availability == .available })
        #expect(probes.contains(back.id))
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    // MARK: - Detection

    private func loaded(_ html: String, at url: URL) async -> WKWebView {
        let configuration = interactiveWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        webView.loadHTMLString(html, baseURL: url)
        #expect(await PageSettle.untilIdle(webView, timeout: .seconds(30)))
        return webView
    }

    private static func page(head: String = "", body: String) -> String {
        "<!doctype html><html lang=\"en\"><head><title>Page</title>\(head)</head><body>\(body)</body></html>"
    }

    private static let longBody = Array(repeating: "<p>\(paragraph)</p>", count: 4).joined()
    private static let thinBody = "<p>\(String(paragraph.prefix(250)))</p>"
    private static let articleMetadata = #"<meta property="og:type" content="article">"#

    @Test func aPageThatNeverAnswersDoesNotHoldTheProbe() async throws {
        let webView = await loaded(
            Self.page(body: "<p>Busy</p><script>setTimeout(() => { for (;;) {} }, 100)</script>"),
            at: Self.articleURL
        )
        try await Task.sleep(for: .milliseconds(300))
        let started = ContinuousClock.now
        #expect(!(await ReaderExtractor.isReaderable(webView)))
        #expect(ContinuousClock.now - started < ReaderExtractor.replyCeiling + .seconds(3))
    }

    @Test func aSiteHomePageNeedsArticleMetadata() async {
        let root = URL(string: "https://example.com/")!

        let plain = await loaded(Self.page(body: Self.longBody), at: root)
        #expect(!(await ReaderExtractor.isReaderable(plain)))

        let tagged = await loaded(Self.page(head: Self.articleMetadata, body: Self.longBody), at: root)
        #expect(await ReaderExtractor.isReaderable(tagged))
    }

    @Test func articleMetadataAdmitsAShortStory() async {
        let plain = await loaded(Self.page(body: Self.thinBody), at: Self.articleURL)
        #expect(!(await ReaderExtractor.isReaderable(plain)))

        let ldJSON = #"<script type="application/ld+json">{"@graph":[{"@type":["NewsArticle"]}]}</script>"#
        let tagged = await loaded(Self.page(head: ldJSON, body: Self.thinBody), at: Self.articleURL)
        #expect(await ReaderExtractor.isReaderable(tagged))
    }

    @Test func textThatIsNotOnScreenDoesNotCount() async {
        let hidden = """
        <style>.consent { display: none; } .drawer { width: 0; overflow: hidden; }</style>
        <div class="consent">\(Self.longBody)</div>
        <div class="drawer">\(Self.longBody)</div>
        <p style="opacity: 0">\(Self.paragraph)</p>
        <form><p>Sign in</p></form>
        """
        let webView = await loaded(Self.page(body: hidden), at: URL(string: "https://example.com/login")!)

        #expect(!(await ReaderExtractor.isReaderable(webView)))
    }

    @Test func aListOfArticlesIsNotAnArticle() async {
        let result = "<article><a href=\"https://example.org\">Result</a> \(Self.paragraph)</article>"
        let results = String(repeating: result, count: 10)
        let webView = await loaded(Self.page(body: results), at: URL(string: "https://example.com/?q=river")!)

        #expect(!(await ReaderExtractor.isReaderable(webView)))
    }

    @Test func aStoryWithRelatedCardsIsStillAnArticle() async {
        let card = "<article><a href=\"/other\">\(Self.paragraph)</a></article>"
        let body = "<article>\(Self.longBody)</article><aside>\(card)\(card)</aside>"
        let webView = await loaded(Self.page(body: body), at: Self.articleURL)

        #expect(await ReaderExtractor.isReaderable(webView))
    }

    @Test func theWatchSeesAnArticleRenderedLate() async throws {
        let webView = await loaded(Self.page(body: "<main></main>"), at: Self.articleURL)
        #expect(!(await ReaderExtractor.isReaderable(webView)))

        let insert = "setTimeout(() => { document.querySelector('main').innerHTML = \(Self.jsString(Self.longBody)); }, 300); true"
        _ = try await webView.evaluateJavaScript(insert)

        #expect(await ReaderExtractor.becomesReaderable(webView, within: .seconds(10)))
    }

    @Test func theWatchGivesUpAfterItsWindow() async {
        let webView = await loaded(Self.page(body: "<main></main>"), at: Self.articleURL)
        let start = ContinuousClock.now

        #expect(!(await ReaderExtractor.becomesReaderable(webView, within: .milliseconds(300))))
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    private static func jsString(_ text: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [text])
        let array = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(array.dropFirst().dropLast())
    }

    // MARK: - Listening

    @Test func listeningReadsTheTitleThenEachBlockInOrder() async {
        let speech = ScriptedSpeech()
        let listener = ReaderListener(output: speech)
        let tab = await openedTab()

        listener.start(Self.article(), in: tab)
        #expect(speech.spoken == ["Headline"])
        #expect(listener.block == ReaderPage.titleBlock)

        speech.finishCurrent()
        #expect(speech.spoken == ["Headline", "One."])
        #expect(listener.block == 0)

        speech.finishCurrent()
        speech.finishCurrent()
        speech.finishCurrent()
        #expect(speech.spoken == ["Headline", "One.", "Two.", "Three."])
        #expect(listener.state == .idle)
        #expect(listener.block == nil)
    }

    @Test func aStaleStopFromTheLastBlockDoesNotSkipAhead() async {
        let speech = ScriptedSpeech()
        let listener = ReaderListener(output: speech)
        let tab = await openedTab()

        listener.start(Self.article(), in: tab)
        speech.begin()
        listener.skip(by: 1)
        speech.end()
        #expect(listener.block == 0)
        #expect(speech.spoken.last == "One.")

        speech.begin()
        speech.end()
        #expect(listener.block == 1)
    }

    @Test func pausingHoldsThePlaceAndResumingRepeatsTheBlock() async {
        let speech = ScriptedSpeech()
        let listener = ReaderListener(output: speech)
        let tab = await openedTab()

        listener.start(Self.article(), in: tab)
        speech.finishCurrent()
        listener.togglePause()
        speech.end()
        #expect(listener.state == .paused)
        #expect(listener.block == 0)
        #expect(speech.spoken == ["Headline", "One."])

        listener.togglePause()
        #expect(listener.state == .playing)
        #expect(speech.spoken == ["Headline", "One.", "One."])
    }

    @Test func leavingTheReaderStopsListening() async {
        let speech = ScriptedSpeech()
        let listener = ReaderListener(output: speech)
        let tab = await openedTab()

        listener.start(Self.article(), in: tab)
        #expect(listener.isListening(to: tab.id))

        tab.reader.close()

        #expect(listener.state == .idle)
        #expect(!listener.isListening(to: tab.id))
    }

    @Test func closingTheTabStopsListening() async {
        let speech = ScriptedSpeech()
        let listener = ReaderListener(output: speech)
        let tab = await openedTab()

        listener.start(Self.article(), in: tab)
        browser.close(tab)

        #expect(listener.state == .idle)
    }

    @Test func longParagraphsAreSpokenInPiecesUnderOneHighlight() async {
        let speech = ScriptedSpeech()
        let listener = ReaderListener(output: speech)
        let tab = await openedTab()
        let long = String(repeating: "A sentence that goes on. ", count: 200)

        listener.start(Self.article(blocks: [long]), in: tab)
        speech.finishCurrent()

        #expect(speech.spoken.last.map { $0.count < long.count } == true)
        #expect(listener.block == 0)
        speech.finishCurrent()
        #expect(listener.block == 0)
        #expect(listener.state == .playing)
    }

    @Test func zoomCommandsResizeReaderText() async {
        let tab = await openedTab()
        let appearance = ReaderAppearance.shared
        appearance.resetSize()
        let pageZoom = tab.webView.pageZoom

        tab.zoomIn()
        #expect(!appearance.isDefaultSize)
        #expect(tab.isZoomed)
        #expect(tab.webView.pageZoom == pageZoom)

        tab.resetZoom()
        #expect(appearance.isDefaultSize)
    }

    private let browser = BrowserModel(database: .temporary())

    private func openedTab() async -> BrowserTab {
        let tab = browser.newTab()
        tab.reader.driver = ReaderDriver(probe: { true }, extract: { Self.article() })
        #expect(await tab.reader.open())
        return tab
    }

    // MARK: - Agent output

    @Test func theAgentGetsTheArticleInPages() {
        let article = Self.article(blocks: ["abcdefghij", "klmnopqrst"])

        let first = AgentToolkit.articleOutput(article, budget: 10, offset: 0)
        #expect(first.hasPrefix("ARTICLE: Headline"))
        #expect(first.contains("abcdefghij"))
        #expect(!first.contains("klmnop"))
        #expect(first.contains("textOffset 10"))

        let rest = AgentToolkit.articleOutput(article, budget: 100, offset: 10)
        #expect(rest.contains("klmnopqrst"))
        #expect(!rest.contains("more characters"))

        #expect(AgentToolkit.articleOutput(nil, budget: 100, offset: 0).hasPrefix("NO ARTICLE"))
    }
}

@MainActor
private final class ScriptedSpeech: SpeechOutput {
    var isMuted = false
    var onSpeakingChange: ((Bool) -> Void)?
    private(set) var spoken: [String] = []

    func speak(_ text: String) {
        spoken.append(text)
    }

    func stopSpeaking() {}

    func begin() {
        onSpeakingChange?(true)
    }

    func end() {
        onSpeakingChange?(false)
    }

    func finishCurrent() {
        begin()
        end()
    }
}

@MainActor
private final class ExtractionGate {
    private var continuation: CheckedContinuation<ReaderArticle?, Never>?

    func wait() async -> ReaderArticle? {
        await withCheckedContinuation { continuation = $0 }
    }

    func untilWaiting() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func release(_ article: ReaderArticle?) {
        continuation?.resume(returning: article)
        continuation = nil
    }
}
