// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

/// The agent's hands, against real pages. Every fixture is a condition the
/// open web presents: duplicate labels, shadow roots, iframes, selects, fields
/// that must be refused, elements that vanish between the read and the act.
/// Real `WKWebView`s rather than mocks, because what is under test is
/// precisely the JavaScript that runs inside WebKit.
@MainActor
@Suite(.serialized, .boundedWebViews)
struct PageDriverTests {
    private static let stage: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        return WKWebView(
            frame: NSRect(x: 0, y: 0, width: 500, height: 400),
            configuration: configuration
        )
    }()

    private func loadedWebView(_ body: String) async -> WKWebView {
        let webView = Self.stage
        webView.loadHTMLString("<!doctype html><html><body>\(body)</body></html>", baseURL: nil)
        #expect(await PageSettle.untilIdle(webView, timeout: .seconds(30)))
        return webView
    }

    private func js(_ webView: WKWebView, _ script: String) async -> Any? {
        try? await webView.evaluateJavaScript(script)
    }

    /// The refs the observation assigned, in the order listed.
    private func refs(in observation: String, matching needle: String) -> [Int] {
        observation
            .components(separatedBy: "\n")
            .filter { $0.contains(needle) }
            .compactMap { line in
                guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
                return Int(line[line.index(after: line.startIndex)..<close])
            }
    }

    // MARK: - Observation

    @Test func numbersEveryControlAndSaysWhatItIs() async {
        let webView = await loadedWebView("""
        <p>Welcome to the shop.</p>
        <button>Add to Bag</button>
        <a href="https://example.com/product">Product page</a>
        <input placeholder="Search">
        """)
        let observation = await PageDriver.readRenderedPage(webView)

        #expect(observation.contains("PAGE TEXT:"))
        #expect(observation.contains("Welcome to the shop."))
        #expect(observation.contains("CONTROLS"))
        #expect(observation.contains("button \"Add to Bag\""))
        #expect(observation.contains("link \"Product page\" → https://example.com/product"))
        #expect(observation.contains("field \"Search\""))
        #expect(!refs(in: observation, matching: "Add to Bag").isEmpty)
    }

    /// The activity trail and the navigation allowlist both read the links
    /// out of an observation. Only anchors count: a bare domain printed in
    /// prose - which is how Hacker News labels every story - is text.
    @Test func onlyAnchorsCountAsLinks() async {
        let webView = await loadedWebView("""
        <p>Discussed on news.ycombinator.com and simonwillison.net today.</p>
        <a href="https://example.com/story">The story</a>
        <a href="https://example.com/story">The story again</a>
        """)
        let observation = await PageDriver.readRenderedPage(webView)
        let links = PageDriver.listedLinks(in: observation)

        #expect(links.map(\.url.absoluteString) == ["https://example.com/story"])
        #expect(links.first?.label == "The story")
    }

    @Test func aLinkListingSurvivesItsOwnPunctuation() {
        let controls: [[String: Any]] = [
            ["r": 1, "k": "link", "l": "Home \u{2192} Shop", "h": "https://example.com/shop", "d": 1],
            ["r": 2, "k": "button", "l": "Buy"],
            ["r": 3, "k": "link", "l": "Mail us", "h": "mailto:hi@example.com"],
        ]
        let links = PageDriver.listedLinks(in: PageDriver.renderControls(controls))

        #expect(links.map(\.url.absoluteString) == ["https://example.com/shop"])
        #expect(links.first?.label == "Home \u{2192} Shop")
    }

    /// The reason refs exist: five "More" buttons are five different rows,
    /// not one row shown once.
    @Test func duplicateLabelsGetDistinctRefs() async {
        let webView = await loadedWebView("""
        <button onclick="window.__hit='first'">More</button>
        <button onclick="window.__hit='second'">More</button>
        <button onclick="window.__hit='third'">More</button>
        """)
        let observation = await PageDriver.readRenderedPage(webView)
        let more = refs(in: observation, matching: "\"More\"")
        #expect(more.count == 3)
        #expect(Set(more).count == 3)
    }

    @Test func clickByRefHitsExactlyTheElementNamed() async throws {
        let webView = await loadedWebView("""
        <button onclick="window.__hit='first'">More</button>
        <button onclick="window.__hit='second'">More</button>
        """)
        let observation = await PageDriver.readRenderedPage(webView)
        let more = refs(in: observation, matching: "\"More\"")
        let second = try #require(more.dropFirst().first)

        let result = await PageDriver.click(ref: second, label: "", in: webView)
        #expect(result.hasPrefix("Clicked"))
        #expect(await js(webView, "window.__hit") as? String == "second")
    }

    @Test func clickByLabelStillWorksAndTakesTheFirstMatch() async {
        let webView = await loadedWebView("""
        <button onclick="window.__hit='a'">Accept cookies</button>
        <button onclick="window.__hit='b'">Accept cookies</button>
        """)
        let result = await PageDriver.click(ref: 0, label: "accept cookies", in: webView)
        #expect(result.hasPrefix("Clicked"))
        #expect(await js(webView, "window.__hit") as? String == "a")
    }

    @Test func aMissingLabelListsWhatIsActuallyThere() async {
        let webView = await loadedWebView("""
        <button>Sign up</button>
        <button>Log in</button>
        """)
        let result = await PageDriver.click(ref: 0, label: "Subscribe", in: webView)
        #expect(result.contains("Nothing matches"))
        #expect(result.contains("sign up"))
        #expect(result.contains("log in"))
    }

    // MARK: - The modern web

    @Test func seesInsideOpenShadowRoots() async {
        let webView = await loadedWebView("""
        <div id="host"></div>
        <script>
          const root = document.getElementById('host').attachShadow({ mode: 'open' });
          root.innerHTML = '<button>Shadow Button</button>';
          root.querySelector('button').addEventListener('click', () => { window.__shadowHit = true; });
        </script>
        """)
        let observation = await PageDriver.readRenderedPage(webView)
        #expect(observation.contains("Shadow Button"))

        let result = await PageDriver.click(ref: 0, label: "Shadow Button", in: webView)
        #expect(result.hasPrefix("Clicked"))
        #expect(await js(webView, "window.__shadowHit") as? Bool == true)
    }

    @Test func seesInsideSameOriginIframes() async {
        let webView = await loadedWebView("""
        <iframe srcdoc="<p>Inside the frame.</p><button onclick='parent.__frameHit = true'>Frame Button</button>"></iframe>
        """)
        // The iframe loads after the main document; poll the observation
        // until its content appears rather than sleeping a guessed amount.
        var observation = ""
        _ = await waitUntil {
            observation = await PageDriver.readRenderedPage(webView)
            return observation.contains("Frame Button")
        }
        #expect(observation.contains("Frame Button"))
        #expect(observation.contains("Inside the frame."))

        let result = await PageDriver.click(ref: 0, label: "Frame Button", in: webView)
        #expect(result.hasPrefix("Clicked"))
        #expect(await js(webView, "window.__frameHit") as? Bool == true)
    }

    @Test func doesNotReadOrControlCrossOriginFrames() async throws {
        let framed = try await HTTPFixtureServer.start(routes: [
            "/framed": .html("<p>Cross-origin secret</p><button>Hidden action</button>"),
        ])
        let framedURL = try framed.url("/framed")
        let top = try await HTTPFixtureServer.start(routes: [
            "/": .html("<h1>Top-level text</h1><iframe src=\"\(framedURL.absoluteString)\"></iframe>"),
        ])
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 500, height: 400),
            configuration: configuration
        )
        webView.load(URLRequest(url: try top.url()))
        #expect(await PageSettle.untilIdle(webView, timeout: .seconds(30)))

        let observation = await PageDriver.readRenderedPage(webView)
        #expect(observation.contains("Top-level text"))
        #expect(!observation.contains("Cross-origin secret"))
        #expect(!observation.contains("Hidden action"))
    }

    @Test func invisibleElementsAreNotOffered() async {
        let webView = await loadedWebView("""
        <button>Visible</button>
        <button style="display:none">Hidden</button>
        <button style="visibility:hidden">Ghost</button>
        """)
        let observation = await PageDriver.readRenderedPage(webView)
        #expect(observation.contains("\"Visible\""))
        #expect(!observation.contains("\"Hidden\""))
        #expect(!observation.contains("\"Ghost\""))
    }

    @Test func aWrapperAndItsInnerControlAreOneRow() async {
        let webView = await loadedWebView("""
        <div role="button" onclick="window.__hit=1">
          <button>Buy tickets</button>
        </div>
        """)
        let observation = await PageDriver.readRenderedPage(webView)
        #expect(refs(in: observation, matching: "Buy tickets").count == 1)
    }

    // MARK: - Staleness and disabled controls

    @Test func aStaleRefSaysSoInsteadOfGuessing() async throws {
        let webView = await loadedWebView(#"<button id="gone">Remove me</button>"#)
        let observation = await PageDriver.readRenderedPage(webView)
        let ref = try #require(refs(in: observation, matching: "Remove me").first)

        _ = await js(webView, "document.getElementById('gone').remove()")
        let result = await PageDriver.click(ref: ref, label: "", in: webView)
        #expect(result.contains("gone"))
        #expect(result.contains("readPage"))
    }

    @Test func aStaleFieldRefDoesNotTypeIntoAReplacement() async throws {
        let webView = await loadedWebView(#"<input id="gone" placeholder="Search">"#)
        let observation = await PageDriver.readRenderedPage(webView)
        let ref = try #require(refs(in: observation, matching: "Search").first)

        _ = await js(webView, "document.getElementById('gone').remove()")
        _ = await js(webView, "document.body.innerHTML = '<input id=\"replacement\" placeholder=\"Search\">'")
        let result = await PageDriver.type(
            text: "private text",
            intoField: "",
            ref: ref,
            submit: false,
            in: webView
        )

        #expect(result.contains("gone"))
        #expect(result.contains("readPage"))
        #expect(await js(webView, "document.getElementById('replacement').value") as? String == "")
    }

    @Test func aStaleSelectRefDoesNotChooseFromAReplacement() async throws {
        let webView = await loadedWebView("""
        <select id="gone" aria-label="Size"><option>Small</option><option>Large</option></select>
        """)
        let observation = await PageDriver.readRenderedPage(webView)
        let ref = try #require(refs(in: observation, matching: "Size").first)

        _ = await js(webView, "document.getElementById('gone').remove()")
        _ = await js(webView, "document.body.innerHTML = '<select id=\"replacement\" aria-label=\"Size\"><option>Small</option><option>Large</option></select>'")
        let result = await PageDriver.selectOption("Large", ref: ref, field: "", in: webView)

        #expect(result.contains("gone"))
        #expect(result.contains("readPage"))
        #expect(await js(webView, "document.getElementById('replacement').value") as? String == "Small")
    }

    @Test func aDisabledControlIsMarkedAndNotClicked() async throws {
        let webView = await loadedWebView(#"<button disabled onclick="window.__hit=1">Continue</button>"#)
        let observation = await PageDriver.readRenderedPage(webView)
        #expect(observation.contains("(disabled)"))

        let ref = try #require(refs(in: observation, matching: "Continue").first)
        let result = await PageDriver.click(ref: ref, label: "", in: webView)
        #expect(result.contains("disabled"))
        #expect(await js(webView, "window.__hit") == nil)
    }

    // MARK: - Typing

    @Test func typesByRefAndFiresTheEventsFrameworksListenFor() async throws {
        let webView = await loadedWebView("""
        <input id="q" placeholder="Search">
        <script>
          window.__events = [];
          const q = document.getElementById('q');
          q.addEventListener('input', () => window.__events.push('input'));
          q.addEventListener('change', () => window.__events.push('change'));
        </script>
        """)
        let observation = await PageDriver.readRenderedPage(webView)
        let ref = try #require(refs(in: observation, matching: "Search").first)

        let result = await PageDriver.type(text: "running shoes", intoField: "", ref: ref, submit: false, in: webView)
        #expect(result.hasPrefix("Typed into “Search”"))
        #expect(await js(webView, "document.getElementById('q').value") as? String == "running shoes")
        let events = await js(webView, "JSON.stringify(window.__events)") as? String
        #expect(events?.contains("input") == true)
        #expect(events?.contains("change") == true)
    }

    @Test func submitReachesTheForm() async {
        let webView = await loadedWebView("""
        <form onsubmit="window.__submitted = true; return false;">
          <input name="q" placeholder="Search">
        </form>
        """)
        let result = await PageDriver.type(text: "shoes", intoField: "Search", ref: 0, submit: true, in: webView)
        #expect(result.contains("submitted"))
        #expect(await js(webView, "window.__submitted") as? Bool == true)
    }

    // MARK: - Selects

    @Test func listsASelectWithItsOptionsAndCurrentChoice() async {
        let webView = await loadedWebView("""
        <label for="size">Size</label>
        <select id="size">
          <option>Small</option><option selected>Medium</option><option>Large</option>
        </select>
        """)
        let observation = await PageDriver.readRenderedPage(webView)
        #expect(observation.contains("select \"Size\" = \"Medium\""))
        #expect(observation.contains("Small | Medium | Large"))
    }

    @Test func choosesAnOptionByRefAndFiresChange() async throws {
        let webView = await loadedWebView("""
        <label for="size">Size</label>
        <select id="size" onchange="window.__changed = this.value">
          <option>Small</option><option selected>Medium</option><option>Large</option>
        </select>
        """)
        let observation = await PageDriver.readRenderedPage(webView)
        let ref = try #require(refs(in: observation, matching: "select \"Size\"").first)

        let result = await PageDriver.selectOption("Large", ref: ref, field: "", in: webView)
        #expect(result.hasPrefix("Selected “Large” in “Size”"))
        #expect(await js(webView, "document.getElementById('size').value") as? String == "Large")
        #expect(await js(webView, "window.__changed") as? String == "Large")
    }

    @Test func choosesAnOptionByTheSelectsLabel() async {
        let webView = await loadedWebView("""
        <label for="country">Country</label>
        <select id="country"><option>France</option><option>Germany</option></select>
        """)
        let result = await PageDriver.selectOption("germany", ref: 0, field: "Country", in: webView)
        #expect(result.hasPrefix("Selected “Germany”"))
    }

    @Test func aMissingOptionListsWhatTheSelectOffers() async throws {
        let webView = await loadedWebView("""
        <label for="size">Size</label>
        <select id="size"><option>Small</option><option>Large</option></select>
        """)
        let observation = await PageDriver.readRenderedPage(webView)
        let ref = try #require(refs(in: observation, matching: "select").first)

        let result = await PageDriver.selectOption("Enormous", ref: ref, field: "", in: webView)
        #expect(result.contains("No option matches"))
        #expect(result.contains("Small | Large"))
    }

    // MARK: - Checkboxes

    @Test func checkboxesReadTheirLabelsAndReportTheirState() async throws {
        let webView = await loadedWebView("""
        <input type="checkbox" id="news">
        <label for="news">Subscribe to the newsletter</label>
        """)
        let observation = await PageDriver.readRenderedPage(webView)
        #expect(observation.contains("checkbox \"Subscribe to the newsletter\" (unchecked)"))

        let ref = try #require(refs(in: observation, matching: "checkbox").first)
        let result = await PageDriver.click(ref: ref, label: "", in: webView)
        #expect(result.hasPrefix("Clicked"))
        #expect(await js(webView, "document.getElementById('news').checked") as? Bool == true)
    }

    // MARK: - Scrolling and reading

    /// "Visible now" has to mean the viewport, not the top of the document -
    /// after a scroll those differ by exactly the amount scrolled.
    @Test func scrollReportsWhatIsActuallyOnScreen() async {
        let webView = await loadedWebView("""
        <p>TOPMARKER at the very top.</p>
        <div style="height: 500px"></div>
        <p>BOTTOMMARKER further down.</p>
        """)
        let result = await PageDriver.scroll(direction: "down", in: webView)
        #expect(result.contains("BOTTOMMARKER"))
        #expect(!result.contains("TOPMARKER"))
    }

    @Test func lookingForReturnsThePartOfThePageAboutIt() async {
        let filler = String(repeating: "Nothing to see in this paragraph of filler prose. ", count: 120)
        let webView = await loadedWebView("""
        <p>\(filler)</p>
        <p>The warranty on this product lasts 24 months from delivery.</p>
        """)
        let plain = await PageDriver.readRenderedPage(webView)
        #expect(!plain.contains("24 months"), "the answer sits past the budget without lookingFor")

        let aimed = await PageDriver.readRenderedPage(webView, lookingFor: "warranty period")
        #expect(aimed.contains("warranty"))
        #expect(aimed.contains("24 months"))
    }

    @Test func anActionWithNeitherRefNorLabelAsksForOne() async {
        let webView = await loadedWebView("<button>Fine</button>")
        let result = await PageDriver.click(ref: 0, label: "", in: webView)
        #expect(result.contains("Say which element"))
    }
}

/// The consent gate, in a suite of its own. Serialized even though the seam is
/// task-local: these share `AgentActionPolicy.shared`'s stored grants, and a
/// grant left by one is a question the next never gets asked.
@MainActor
@Suite(.serialized, .boundedWebViews)
struct AgentConsentGateTests {
    private func loadedWebView(_ body: String) async -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 500, height: 400),
            configuration: configuration
        )
        webView.loadHTMLString("<!doctype html><html><body>\(body)</body></html>", baseURL: nil)
        #expect(await PageSettle.untilIdle(webView, timeout: .seconds(30)))
        return webView
    }

    private func js(_ webView: WKWebView, _ script: String) async -> Any? {
        try? await webView.evaluateJavaScript(script)
    }

    private func refs(in observation: String, matching needle: String) -> [Int] {
        observation
            .components(separatedBy: "\n")
            .filter { $0.contains(needle) }
            .compactMap { line -> Int? in
                guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
                return Int(line[line.index(after: line.startIndex)..<close])
            }
    }

    private func firstRef(in observation: String, matching needle: String) -> Int? {
        refs(in: observation, matching: needle).first
    }

    /// The consent question runs on the element's own label, so addressing a
    /// payment button by number instead of by name changes nothing - and the
    /// user's decline is final: no click, and the model is told to stop
    /// rather than to try another route.
    @Test func aDeclinedConsequentialClickDoesNotHappen() async throws {
        let webView = await loadedWebView(#"<button onclick="window.__paid=1">Place order</button>"#)
        let observation = await PageDriver.readRenderedPage(webView)
        let ref = try #require(firstRef(in: observation, matching: "Place order"))

        var asked: (label: String, category: SensitiveAction.Category)?
        let result = await AgentActionConsent.$decisionForTesting.withValue(.init({ label, category, _ in
            asked = (label, category)
            return .decline
        })) {
            await PageDriver.click(ref: ref, label: "", in: webView)
        }
        #expect(asked?.label == "Place order")
        #expect(asked?.category == .purchase)
        #expect(result.contains("declined"))
        #expect(result.contains("do not try another way"))
        #expect(await js(webView, "window.__paid") == nil)
    }

    /// And the user saying yes is equally final: the click proceeds exactly
    /// as an ordinary one would.
    @Test func anAllowedConsequentialClickProceeds() async throws {
        let webView = await loadedWebView(#"<button onclick="window.__paid=1">Place order</button>"#)
        let observation = await PageDriver.readRenderedPage(webView)
        let ref = try #require(firstRef(in: observation, matching: "Place order"))

        let result = await AgentActionConsent.$decisionForTesting.withValue(.init({ _, _, _ in .allowOnce })) {
            await PageDriver.click(ref: ref, label: "", in: webView)
        }
        #expect(result.hasPrefix("Clicked"))
        #expect(await js(webView, "window.__paid") as? Int == 1)
    }

    @Test func aDeceptiveLabelCannotHideAConsequentialForm() async throws {
        let webView = await loadedWebView("""
        <form aria-label="Checkout" onsubmit="window.__paid=1; return false;">
          <p>Review and complete purchase</p>
          <button>Continue</button>
        </form>
        """)
        let observation = await PageDriver.readRenderedPage(webView)
        let ref = try #require(firstRef(in: observation, matching: "Continue"))

        var asked: (label: String, category: SensitiveAction.Category)?
        let result = await AgentActionConsent.$decisionForTesting.withValue(.init({ label, category, _ in
            asked = (label, category)
            return .decline
        })) {
            await PageDriver.click(ref: ref, label: "", in: webView)
        }

        #expect(asked?.label == "Continue")
        #expect(asked?.category == .purchase)
        #expect(result.contains("declined"))
        #expect(await js(webView, "window.__paid") == nil)
    }

    @Test func anOrdinaryContinueButtonDoesNotTriggerConsequentialConsent() async throws {
        let webView = await loadedWebView("""
        <form onsubmit="window.__continued=1; return false;">
          <p>Continue profile setup</p>
          <button>Continue</button>
        </form>
        """)
        let observation = await PageDriver.readRenderedPage(webView)
        let ref = try #require(firstRef(in: observation, matching: "Continue"))

        var asked = false
        let result = await AgentActionConsent.$decisionForTesting.withValue(.init({ _, _, _ in
            asked = true
            return .decline
        })) {
            await PageDriver.click(ref: ref, label: "", in: webView)
        }

        #expect(!asked)
        #expect(result.hasPrefix("Clicked"))
        #expect(await js(webView, "window.__continued") as? Int == 1)
    }

    @Test func aSensitiveFieldIsRefusedEvenByRef() async throws {
        let webView = await loadedWebView(#"<input type="password" placeholder="Password">"#)
        let observation = await PageDriver.readRenderedPage(webView)
        let ref = try #require(refs(in: observation, matching: "Password").first)

        let result = await PageDriver.type(text: "hunter2", intoField: "", ref: ref, submit: false, in: webView)
        #expect(result.contains("sensitive") || result.contains("password"))
        #expect(await js(webView, "document.querySelector('input').value") as? String == "")
    }

    /// Refusing to *write* a secret is half the duty. An observation is sent
    /// verbatim to whichever provider the user configured, so a value already
    /// in the field - a password manager fills one on load, without the user
    /// touching the page - must not travel with it.
    @Test func anObservationNeverCarriesASensitiveValue() async {
        let webView = await loadedWebView("""
        <input name="user" value="ada@example.com">
        <input type="password" name="password" value="hunter2-SECRET">
        """)
        let observation = await PageDriver.readRenderedPage(webView)

        #expect(!observation.contains("hunter2-SECRET"))
        // Still visible as a field, and still known to be filled: the model
        // has to be able to tell a completed form from an empty one.
        #expect(observation.contains("field \"password\" (password) = (filled, hidden)"))
        #expect(observation.contains("ada@example.com"))
    }

    /// The same predicate the writing half uses, so the two cannot drift:
    /// a card number is caught by its `autocomplete`, a code by its label.
    @Test func anObservationHidesPaymentAndCodeValuesToo() async {
        let webView = await loadedWebView("""
        <input autocomplete="cc-number" placeholder="Card number" value="4111111111111111">
        <input autocomplete="cc-csc" placeholder="CVC" value="737">
        <input placeholder="One-time code" value="908321">
        <input placeholder="Delivery note" value="leave at the door">
        """)
        let observation = await PageDriver.readRenderedPage(webView)

        #expect(!observation.contains("4111111111111111"))
        #expect(!observation.contains("908321"))
        #expect(observation.contains("field \"Card number\" = (filled, hidden)"))
        // An ordinary field is untouched - the denylist errs toward hiding,
        // but it is still a denylist, not a blanket.
        #expect(observation.contains("leave at the door"))
    }

    /// An empty sensitive field says so, rather than going quiet and leaving
    /// "is the form filled in?" unanswerable.
    @Test func anEmptySensitiveFieldReportsThatItIsEmpty() async {
        let webView = await loadedWebView(#"<input type="password" placeholder="Password">"#)
        let observation = await PageDriver.readRenderedPage(webView)

        #expect(observation.contains("= (empty)"))
    }

    /// A grant is scoped to a site, so a page with no host to scope it to
    /// must never count as granted - otherwise `data:`, `file:` and
    /// `about:` pages would walk through the gate unasked.
    @Test func aPageWithNoHostIsNeverAlreadyAllowed() {
        for category in SensitiveAction.Category.allCases {
            #expect(!AgentActionPolicy.shared.isAlwaysAllowed(category, host: nil))
            #expect(!AgentActionPolicy.shared.isAlwaysAllowed(category, host: ""))
        }
    }
}
