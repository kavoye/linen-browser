// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import Translation
import WebKit

@testable import Linen

@MainActor
struct PageTranslationTests {
    private func tagged(_ parts: [(String, Int?)]) -> AttributedString {
        var result = AttributedString()
        for (text, node) in parts {
            var part = AttributedString(text)
            part.link = node.map { URL(string: "linen-node:\($0)")! }
            result += part
        }
        return result
    }

    @Test func translatedRunsGoBackToTheNodesTheyCameFrom() {
        let translated = tagged([("Click ", 4), ("here ", 5), ("to continue", 6), ("!", nil)])
        let texts = PageTranslationRuns.distribute(translated, fallback: "", over: [4, 5, 6, 7])
        #expect(texts == [4: "Click ", 5: "here ", 6: "to continue!", 7: ""])
    }

    @Test func untaggedOrForeignRunsJoinTheFirstNode() {
        let translated = tagged([("Hello ", nil), ("world", 99)])
        #expect(PageTranslationRuns.distribute(translated, fallback: "", over: [1, 2]) == [1: "Hello world", 2: ""])
        #expect(PageTranslationRuns.distribute(nil, fallback: "Hello world", over: [1, 2]) == [1: "Hello world", 2: ""])
    }

    @Test func requestTagsEverySegment() {
        let request = PageTranslationRuns.request(for: [.init(node: 3, text: "Klicken Sie "), .init(node: 8, text: "hier")])
        #expect(String(request.characters) == "Klicken Sie hier")
        #expect(request.runs.map { $0.link?.absoluteString } == ["linen-node:3", "linen-node:8"])
    }

    @Test func languagesMatchByLanguageAndChineseScript() {
        let english = Locale.Language(identifier: "en-US")
        #expect(TranslationLanguage.matches(english, Locale.Language(identifier: "en-GB")))
        #expect(!TranslationLanguage.matches(english, Locale.Language(identifier: "de")))
        #expect(!TranslationLanguage.matches(Locale.Language(identifier: "zh-Hans"), Locale.Language(identifier: "zh-Hant")))
        #expect(TranslationLanguage.matches(Locale.Language(identifier: "zh-CN"), Locale.Language(identifier: "zh-Hans")))
    }

    @Test func offersPreferredLanguagesOnlyForPagesTheReaderCannotRead() {
        let preferred = ["en-GB", "uk-UA", "en-US"]
        let japanese = TranslationLanguage.targets(for: Locale.Language(identifier: "ja"), preferring: "", preferred: preferred)
        #expect(japanese.map(TranslationLanguage.key) == ["en", "uk"])

        let ukrainian = TranslationLanguage.targets(for: Locale.Language(identifier: "uk"), preferring: "", preferred: preferred)
        #expect(ukrainian.isEmpty)

        let remembered = TranslationLanguage.targets(for: Locale.Language(identifier: "ja"), preferring: "uk", preferred: preferred)
        #expect(remembered.map(TranslationLanguage.key) == ["uk", "en"])

        let pageLanguage = TranslationLanguage.targets(for: Locale.Language(identifier: "uk"), preferring: "uk", preferred: ["en"])
        #expect(pageLanguage.map(TranslationLanguage.key) == ["en"])
    }

    @Test func requestsForTheSamePairShareOneDownload() async {
        let downloads = TranslationDownloads()
        let japanese = Locale.Language(identifier: "ja")
        let english = Locale.Language(identifier: "en")
        let first = Task { await downloads.prepare(.fast, from: japanese, to: english) }
        let second = Task { await downloads.prepare(.fast, from: japanese, to: english) }
        let asked = await waitUntil { downloads.configuration != nil }
        #expect(asked)
        await Task.yield()

        await downloads.run { true }
        let results = (await first.value, await second.value)
        #expect(results == (true, true))
        #expect(downloads.configuration == nil)
    }

    @Test func aDeclinedDownloadIsOfferedAgainOnTheNextRequest() async {
        let downloads = TranslationDownloads()
        let russian = Locale.Language(identifier: "ru")
        let ukrainian = Locale.Language(identifier: "uk")
        let first = Task { await downloads.prepare(.fast, from: russian, to: ukrainian) }
        let asked = await waitUntil { downloads.configuration != nil }
        #expect(asked)
        await downloads.run { false }
        #expect(await first.value == false)

        let again = Task { await downloads.prepare(.fast, from: russian, to: ukrainian) }
        #expect(await waitUntil { downloads.configuration != nil })
        await downloads.run { true }
        #expect(await again.value)
    }

    @Test func aDifferentPairReplacesTheWaitingDownload() async {
        let downloads = TranslationDownloads()
        let english = Locale.Language(identifier: "en")
        let ukrainian = Task { await downloads.prepare(.fast, from: Locale.Language(identifier: "ja"), to: Locale.Language(identifier: "uk")) }
        let asked = await waitUntil { downloads.configuration != nil }
        #expect(asked)
        let german = Task { await downloads.prepare(.fast, from: Locale.Language(identifier: "de"), to: english) }

        #expect(await ukrainian.value == false)
        #expect(downloads.configuration?.source.map(TranslationLanguage.key) == "de")
        await downloads.run { true }
        #expect(await german.value)
    }

    @Test func aCancelledDownloadEndsTheWaitButIsOfferedAgain() async {
        let downloads = TranslationDownloads()
        let russian = Locale.Language(identifier: "ru")
        let ukrainian = Locale.Language(identifier: "uk")
        let first = Task { await downloads.prepare(.fast, from: russian, to: ukrainian) }
        #expect(await waitUntil { downloads.configuration != nil })
        let host = Task {
            await downloads.run {
                try? await Task.sleep(for: .seconds(30))
                return false
            }
        }
        host.cancel()
        await host.value
        #expect(await first.value == false)

        let again = Task { await downloads.prepare(.fast, from: russian, to: ukrainian) }
        #expect(await waitUntil(timeout: .seconds(5)) { downloads.configuration != nil })
        await downloads.run { true }
        #expect(await again.value)
    }

    @Test func aHostThatGoesAwayEndsTheWaitButIsOfferedAgain() async {
        let downloads = TranslationDownloads()
        let japanese = Locale.Language(identifier: "ja")
        let english = Locale.Language(identifier: "en")
        let first = Task { await downloads.prepare(.fast, from: japanese, to: english) }
        #expect(await waitUntil { downloads.configuration != nil })

        downloads.abandon()

        #expect(await first.value == false)
        #expect(downloads.configuration == nil)
        let again = Task { await downloads.prepare(.fast, from: japanese, to: english) }
        #expect(await waitUntil(timeout: .seconds(5)) { downloads.configuration != nil })
        await downloads.run { true }
        #expect(await again.value)
    }

    @Test func movingWithinThePageForgetsTheDetectedLanguage() {
        let translation = PageTranslation()
        translation.offer([Locale.Language(identifier: "en")])
        let before = translation.document

        translation.pageMoved()
        #expect(translation.targets.isEmpty)
        #expect(translation.document == before + 1)

        _ = translation.begin(to: Locale.Language(identifier: "en"))
        translation.offer([Locale.Language(identifier: "en")])
        translation.pageMoved()
        #expect(translation.targets.count == 1)
    }

    @Test func detectionReadsTheTextBeforeTheDeclaredLanguage() throws {
        let japanese = PageTranslationSample(
            declaredLanguage: "en",
            text: "今日は天気がとても良いので、公園まで散歩に行きました。桜がきれいに咲いていました。"
        )
        let detected = try #require(TranslationLanguage.detect(japanese))
        #expect(TranslationLanguage.key(detected) == "ja")

        let shell = PageTranslationSample(declaredLanguage: "de-DE", text: "YouTube")
        #expect(TranslationLanguage.detect(shell) == nil)
    }

    @Test func detectionIsNotDecidedByTheTitleAndMenu() throws {
        let apple = PageTranslationSample(
            declaredLanguage: "en-US",
            text: """
            OS - macOS 27 Golden Gate - Apple
            Apple
            Overview
            iOS
            macOS
            iPadOS
            watchOS
            visionOS
            Apple Intelligence
            Siri AI is rolling out in English.
            Explore what’s new for macOS 27.
            New Siri AI. An even more capable AI assistant with expanded intelligence to be more helpful every day.
            Type or talk naturally with Siri AI to find what you need and get more done.
            """
        )
        let detected = try #require(TranslationLanguage.detect(apple))
        #expect(TranslationLanguage.key(detected) == "en")
    }

    @Test func thinEvidenceDefersToAPlausibleDeclaredLanguage() throws {
        let loading = PageTranslationSample(
            declaredLanguage: "en-us",
            text: "App Store Connect\nCopia: Clipboard Manager\nDistributionAnalyticsTestFlight"
        )
        let detected = try #require(TranslationLanguage.detect(loading))
        #expect(TranslationLanguage.key(detected) == "en")

        let german = PageTranslationSample(declaredLanguage: "en", text: "Startseite\nNachrichten und aktuelle Themen aus Deutschland")
        #expect(TranslationLanguage.detect(german).map(TranslationLanguage.key) == "de")
    }

    @Test func alreadyTranslatedBlocksAreSkipped() async {
        let skipper = TranslationLanguage.Skipper(source: Locale.Language(identifier: "de"), target: Locale.Language(identifier: "en"))
        let english = await skipper.isAlreadyTarget([.init(node: 0, text: "This paragraph is already written in English.")])
        let german = await skipper.isAlreadyTarget([.init(node: 0, text: "Dieser Absatz ist noch auf Deutsch geschrieben.")])
        let short = await skipper.isAlreadyTarget([.init(node: 0, text: "Login")])
        #expect(english)
        #expect(!german)
        #expect(!short)
    }

    @Test func onlyTheNewestRequestChangesTheState() {
        let translation = PageTranslation()
        let ukrainian = translation.begin(to: Locale.Language(identifier: "uk"))
        let english = translation.begin(to: Locale.Language(identifier: "en"))

        translation.abandon(ukrainian, in: nil)
        #expect(translation.phase == .translating)
        #expect(translation.target.map(TranslationLanguage.key) == "en")

        translation.showOriginal(in: nil)
        #expect(!translation.isCurrent(english))
        #expect(translation.phase == .original)
        #expect(translation.target == nil)
    }

    @Test func translationPreferencesPersistAndReachOtherProfiles() throws {
        let suiteName = TestDefaults.name("PageTranslationTests")
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = BrowserSettings(defaults: defaults)
        let other = BrowserSettings(defaults: defaults)
        let japanese = Locale.Language(identifier: "ja")

        settings.translationTarget = Locale.Language(identifier: "de-AT")
        settings.setAlwaysTranslates(true, japanese)

        #expect(other.translationTargetID == "de")
        #expect(other.alwaysTranslates(Locale.Language(identifier: "ja-JP")))
        let restored = BrowserSettings(defaults: defaults)
        #expect(restored.alwaysTranslates(japanese))
        #expect(restored.translationTargetID == "de")

        restored.setAlwaysTranslates(false, japanese)
        restored.resetToDefaults()
        #expect(restored.translationTargetID.isEmpty)
        #expect(!BrowserSettings(defaults: defaults).alwaysTranslates(japanese))
    }

    // MARK: - Page script

    private func load(_ html: String) async throws -> WKWebView {
        let configuration = interactiveWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        view.loadHTMLString("<!doctype html><body>" + html, baseURL: URL(string: "https://news.example/"))
        #expect(await PageSettle.untilIdle(view, timeout: .seconds(20)))
        let loaded = await waitUntil {
            guard !view.isLoading else { return false }
            let state = try? await view.evaluateJavaScript("document.readyState")
            return state as? String == "complete"
        }
        #expect(loaded)
        return view
    }

    private func texts(_ blocks: [[PageTranslationSegment]]) -> [String] {
        blocks.map { $0.map(\.text).joined() }
    }

    @Test(.boundedWebViews) func scriptGroupsInlineTextAndSkipsCodeAndOptOuts() async throws {
        let view = try await load(#"""
        <p id="lead">Klicken Sie <a href="/x">hier</a>, um <b>fortzufahren</b>.</p>
        <p>Erste Zeile<br>Zweite Zeile</p>
        <p>Bitte <a href="/a">hier</a> <b>jetzt</b> klicken</p>
        <pre>let wert = 1</pre><code>wert()</code><p translate="no">Linen</p><p class="notranslate">Linen</p>
        <script>var text = "nicht übersetzen";</script><p>1234</p>
        """#)
        let token = try #require(await PageTranslationScript.start(in: view))
        let blocks = try #require(await PageTranslationScript.next(limit: 10, token: token, in: view))

        #expect(texts(blocks) == [
            "Klicken Sie hier, um fortzufahren.", "Erste Zeile", "Zweite Zeile", "Bitte hier jetzt klicken",
        ])
        #expect(blocks.first?.count == 5)
    }

    @Test(.boundedWebViews) func applyReplacesTextAndRestoreBringsBackTheOriginal() async throws {
        let view = try await load(#"<p id="lead">Klicken Sie <a href="/x">hier</a>.</p>"#)
        let token = try #require(await PageTranslationScript.start(in: view))
        let segments = try #require(await PageTranslationScript.next(limit: 4, token: token, in: view)?.first)
        let nodes = segments.map(\.node)
        try #require(nodes.count == 3)

        await PageTranslationScript.apply([nodes[0]: "Click ", nodes[1]: "here", nodes[2]: "."], in: view)
        #expect(try await view.evaluateJavaScript("lead.textContent") as? String == "Click here.")
        #expect(try await view.evaluateJavaScript("lead.querySelector('a').getAttribute('href')") as? String == "/x")

        await PageTranslationScript.restore(in: view)
        #expect(try await view.evaluateJavaScript("lead.textContent") as? String == "Klicken Sie hier.")
        #expect(await PageTranslationScript.next(limit: 4, token: token, in: view) == nil)
    }

    @Test(.boundedWebViews) func restoreLeavesTextThePageChangedItself() async throws {
        let view = try await load(#"<p id="lead">Guten Morgen</p>"#)
        let token = try #require(await PageTranslationScript.start(in: view))
        let node = try #require(await PageTranslationScript.next(limit: 4, token: token, in: view)?.first?.first?.node)
        await PageTranslationScript.apply([node: "Good morning"], in: view)
        _ = try await view.evaluateJavaScript("lead.firstChild.nodeValue = 'Guten Abend'")

        await PageTranslationScript.restore(in: view)
        #expect(try await view.evaluateJavaScript("lead.textContent") as? String == "Guten Abend")
    }

    @Test(.boundedWebViews) func restartingRetiresTheEarlierRun() async throws {
        let view = try await load("<p>Erster Absatz</p><p>Zweiter Absatz</p>")
        let first = try #require(await PageTranslationScript.start(in: view))
        let second = try #require(await PageTranslationScript.start(in: view))

        #expect(second != first)
        #expect(await PageTranslationScript.next(limit: 4, token: first, in: view) == nil)
        let blocks = try #require(await PageTranslationScript.next(limit: 4, token: second, in: view))
        #expect(texts(blocks) == ["Erster Absatz", "Zweiter Absatz"])
    }

    @Test(.boundedWebViews) func contentAddedLaterIsPickedUp() async throws {
        let view = try await load("<p>Erster Absatz</p><div id='feed'></div>")
        let token = try #require(await PageTranslationScript.start(in: view))
        _ = await PageTranslationScript.next(limit: 4, token: token, in: view)

        let waiting = Task { await PageTranslationScript.next(limit: 4, token: token, in: view) }
        _ = try await view.evaluateJavaScript("feed.innerHTML = '<p>Neuer <i>Beitrag</i></p>'")
        let blocks = try #require(await waiting.value)
        #expect(texts(blocks) == ["Neuer Beitrag"])
    }

    @Test(.boundedWebViews) func closingATranslatedTabEndsItsPendingWait() async throws {
        let model = BrowserModel(database: .temporary())
        let tab = model.ensureActiveTab()
        tab.realizeDeferredSession()
        #expect(await PageSettle.untilIdle(tab.webView, timeout: .seconds(30)))
        tab.webView.loadHTMLString("<!doctype html><body><p>Erster Absatz</p>", baseURL: URL(string: "https://news.example/"))
        #expect(await PageSettle.untilIdle(tab.webView, timeout: .seconds(30)))
        let view = tab.webView
        let token = try #require(await PageTranslationScript.start(in: view))
        _ = await PageTranslationScript.next(limit: 4, token: token, in: view)
        let waiting = Task { await PageTranslationScript.next(limit: 4, token: token, in: view) }
        try await Task.sleep(for: .milliseconds(200))
        _ = tab.translation.begin(to: Locale.Language(identifier: "en"))

        tab.detach()

        let elapsed = await ContinuousClock().measure { _ = await waiting.value }
        #expect(elapsed < .seconds(10))
    }

    @Test(.boundedWebViews) func visibleBlocksComeFirst() async throws {
        let view = try await load(#"""
        <p style="position: absolute; top: 2500px">Weit unten</p><p>Ganz oben</p>
        """#)
        let token = try #require(await PageTranslationScript.start(in: view))
        let blocks = try #require(await PageTranslationScript.next(limit: 1, token: token, in: view))
        #expect(texts(blocks) == ["Ganz oben"])
    }
}
