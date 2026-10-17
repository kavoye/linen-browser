// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct PageInteractionTests {
    private func page(_ body: String) async -> WKWebView {
        let configuration = interactiveWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 500, height: 400), configuration: configuration)
        view.loadHTMLString("<!doctype html><body>\(body)</body>", baseURL: nil)
        #expect(await PageSettle.untilIdle(view, timeout: .seconds(20)))
        return view
    }

    private func js(_ view: WKWebView, _ script: String) async -> Any? {
        try? await view.evaluateJavaScript(script)
    }

    @Test func pageTextKeepsListItemsOnTheirOwnLines() async {
        let view = await page("<h1>Dinner</h1><ul><li>Pie, <b>50</b> minutes</li><li>Risotto, vegetarian</li><li>Salmon</li></ul>")
        let snapshot = await PageDriver.snapshot(view)

        #expect(snapshot.contains("Dinner\nPie, 50 minutes\nRisotto, vegetarian\nSalmon"), "\(snapshot)")
    }

    @Test func valuesTheRequestGivesAreMatchedToTheFormControls() {
        let party = PageDriver.FormControl(ref: 5, label: "Party size", kind: "select", value: "2", options: ["2", "3", "4", "5"])
        let day = PageDriver.FormControl(ref: 6, label: "Day", kind: "select", value: "Thursday", options: ["Thursday", "Friday"])
        let booking = PageDriver.pendingValues(request: "Book a table for 4 people on Friday at 19:00 under the name Ada.", controls: [party, day])
        #expect(booking.map(\.value) == ["4", "Friday"])
        #expect(booking.first?.tool == "selectOption")

        let quantity = PageDriver.FormControl(ref: 5, label: "Quantity", kind: "number", value: "1")
        #expect(PageDriver.pendingValues(request: "Add two Aster desk lamps to the cart", controls: [quantity]).first?.value == "2")
        #expect(PageDriver.pendingValues(request: "Add the Aster lamp to the cart", controls: [quantity]).isEmpty)
        #expect(PageDriver.pendingValues(request: "Add 2 lamps and 3 shades", controls: [quantity]).isEmpty)

        let section = PageDriver.FormControl(ref: 7, label: "Section", kind: "select", value: "B", options: ["A", "B"])
        #expect(PageDriver.pendingValues(request: "Book a table on Friday", controls: [section]).isEmpty)
        #expect(PageDriver.pendingValues(request: "Find 2 rooms for the 2027 conference", controls: [quantity]).first?.value == "2")
        #expect(PageDriver.pendingValues(request: "Show events in 2027", controls: [quantity]).isEmpty)

        let price = PageDriver.FormControl(ref: 5, label: "Maximum price", kind: "number", value: "")
        #expect(PageDriver.pendingValues(request: "Show only textiles under $50", controls: [price]).first?.value == "50")
        #expect(PageDriver.pendingValues(request: "Show only textiles under $50", controls: [quantity]).isEmpty)
    }

    @Test func aFormIsHeldOnceUntilTheRequestedValuesAreSet() async {
        let view = await page("""
            <form onsubmit='window.sent=(window.sent||0)+1;return false'>\
            <label>Day <select><option>Thursday</option><option>Friday</option></select></label><button>Next</button></form>
            """)
        _ = await PageDriver.snapshot(view)
        let constraints = AgentRequestConstraints(request: "Book a table on Friday")

        let held = await PageDriver.click(ref: 2, label: "Next", in: view, constraints: constraints)
        let second = await PageDriver.click(ref: 2, label: "Next", in: view, constraints: constraints)

        #expect(held.contains("“Day” to Friday (selectOption with ref 1)"), "\(held)")
        #expect(held.hasSuffix("then use “Next” again."), "\(held)")
        #expect(second.hasPrefix("Clicked"), "\(second)")
    }

    @Test func aQuantityFromTheRequestIsSetBeforeAddingToTheCart() async {
        let view = await page("""
            <header><nav><a href="/">Home</a> · <a href="/lamps">Lamps</a></nav></header><main><h1>Aster desk lamp</h1><p>Price $129</p>
            <form onsubmit='window.sent=1;return false'><input type="hidden" name="product" value="aster">\
            <label>Quantity <input type="number" name="qty" value="1" min="1"></label><button>Add to cart</button></form></main>
            """)
        _ = await PageDriver.snapshot(view)
        let request = AgentRequestConstraints(request: "Add two Aster desk lamps to the cart, then tell me the cart total.")

        let held = await PageDriver.click(ref: 4, label: "Add to cart", in: view, constraints: request)

        #expect(held.contains("“Quantity” to 2 (typeOnPage with ref 3)"), "\(held)")

    }

    @Test func anEarlierReadOfTheSameDocumentStillWorks() async throws {
        let view = await page("<button onclick='window.hit=true'>Lamps</button>")
        _ = await PageDriver.snapshot(view)
        let first = try #require(PageDriver.observation(in: view)?.id)
        _ = await PageDriver.snapshot(view, lookingFor: "price")

        let output = await PageDriver.$expectedObservation.withValue(first) {
            await PageDriver.click(ref: 1, label: "Lamps", in: view)
        }

        #expect(output.hasPrefix("Clicked"), "\(output)")
    }

    @Test func aLinkFromThePreviousPageSuggestsGoingBack() async {
        let view = await page("<a href='#a'>Aster desk lamp</a> <a href='#b'>Birch desk lamp</a>")
        _ = await PageDriver.snapshot(view)
        view.loadHTMLString("<!doctype html><body><h1>Aster desk lamp</h1><p>Price $129</p><button>Add to cart</button></body>", baseURL: nil)
        _ = await PageSettle.untilIdle(view, timeout: .seconds(10))

        let read = await PageDriver.snapshot(view, lookingFor: "Birch desk lamp price")
        let click = await PageDriver.click(ref: 1, label: "Birch desk lamp", in: view)

        #expect(read.contains("“Birch desk lamp” was a link on the previous page: use goBack"), "\(read)")
        #expect(click.contains("“Birch desk lamp” was a link on the previous page"), "\(click)")
    }

    @Test func submittingFromAFieldIsHeldForTheRequestedValues() async {
        let view = await page("""
            <form onsubmit='window.sent=1;return false'><label>Guests <select><option>2</option><option>4</option></select></label>\
            <label>Name <input></label></form>
            """)
        _ = await PageDriver.snapshot(view)

        let held = await PageDriver.type(text: "Ada", intoField: "Name", ref: 2, submit: true, in: view,
                                         constraints: AgentRequestConstraints(request: "Book for 4 guests under Ada"))

        #expect(held.hasSuffix("Set them first, then submit again."), "\(held)")
    }

    @Test func onlyRecentReadsOfAPageStayValid() {
        var observation = PageObservation(id: "0", documentID: "doc", url: "u", refs: [1])
        for index in 1...10 {
            observation = observation.next(id: String(index), refs: [index])
        }

        #expect(observation.listed("9") == [9])
        #expect(observation.listed("2") == [2])
        #expect(observation.listed("1") == nil)
        #expect(observation.listed(nil) == [10])
    }

    @Test func readOnlyDatePickerExposesClickableDays() async {
        let view = await page("""
            <input id='date' aria-label='Departure date' readonly value='September 23'>
            <div id='calendar' hidden><h3>September</h3>
              <div role='gridcell' tabindex='0' aria-disabled='true'>22</div>
              <div id='day' role='gridcell' tabindex='0'><div>29</div></div>
              <div role='gridcell'>Static cell</div>
              <div role='gridcell' tabindex='0'><button>30</button></div>
            </div>
            <script>
              document.querySelector('#date').addEventListener('click', () => document.querySelector('#calendar').hidden=false);
              document.querySelector('#day').addEventListener('click', () => {
                document.querySelector('#date').value='September 29'; document.querySelector('#calendar').hidden=true;
              });
            </script>
            """)
        let initial = await PageDriver.snapshot(view)
        #expect(initial.contains("(read-only)"))
        let calendar = await PageDriver.click(ref: 0, label: "Departure date", in: view)
        #expect(calendar.contains("button \"29\""))
        #expect(calendar.contains("button \"22\" (disabled)"))
        #expect(!calendar.contains("button \"Static cell\""))
        #expect(calendar.components(separatedBy: "button \"30\"").count == 2)
        let disabled = await PageDriver.click(ref: 0, label: "22", in: view)
        #expect(disabled.contains("disabled"))
        let selected = await PageDriver.click(ref: 0, label: "29", in: view)
        #expect(selected.hasPrefix("Clicked"))
        #expect(await js(view, "document.querySelector('#date').value") as? String == "September 29")
    }

    @Test func observationCannotBeReusedAfterNavigationOrRetargeting() async throws {
        let view = await page("<button id='a' onclick='window.hit=true'>Ordinary action</button>")
        _ = await PageDriver.snapshot(view)
        _ = await js(view, "document.querySelector('button').textContent='Delete account'")
        #expect(await PageDriver.click(ref: 1, label: "", in: view) == PageDriver.staleMessage)
        #expect(await js(view, "window.hit === undefined") as? Bool == true)
        view.loadHTMLString("<button onclick='window.hit=true'>New document</button>", baseURL: nil)
        #expect(await PageSettle.untilIdle(view, timeout: .seconds(20)))
        #expect(await PageDriver.click(ref: 1, label: "", in: view) == PageDriver.staleMessage)
        #expect(await js(view, "window.hit === undefined") as? Bool == true)
    }

    @Test func coveredAndDisabledControlsDoNotRunHandlers() async {
        let view = await page(
            """
            <button style='position:absolute;left:20px;top:20px' onclick='window.hit=true'>Covered</button>
            <div style='position:fixed;inset:0;background:white;z-index:10'></div>
            <select disabled><option>A</option><option>B</option></select>
            """)
        _ = await PageDriver.snapshot(view)
        #expect(!(await PageDriver.click(ref: 1, label: "", in: view)).hasPrefix("Clicked"))
        #expect(!(await PageDriver.selectOption("B", ref: 2, field: "", in: view)).hasPrefix("Selected"))
        #expect(await js(view, "window.hit === undefined && document.querySelector('select').value === 'A'") as? Bool == true)
    }

    @Test func aMovingControlIsNotClickedUntilItSettles() async {
        let view = await page(
            """
            <style>@keyframes move { from { transform:translateX(0) } to { transform:translateX(300px) } }
            button { animation:move 1s infinite alternate linear }</style>
            <button onclick='window.hit=true'>Moving target</button>
            """)
        _ = await PageDriver.snapshot(view)
        #expect(!(await PageDriver.click(ref: 1, label: "", in: view)).hasPrefix("Clicked"))
        #expect(await js(view, "window.hit === undefined") as? Bool == true)
        _ = await js(view, "document.querySelector('button').style.animation='none'")
        #expect((await PageDriver.click(ref: 1, label: "", in: view)).hasPrefix("Clicked"))
    }

    @Test func aStillControlOnABusyPageIsClicked() async {
        let view = await page(
            """
            <button onclick='window.hit=true'>Busy target</button>
            <script>setInterval(() => { const end = performance.now() + 700; while (performance.now() < end) {} }, 0)</script>
            """)
        _ = await PageDriver.snapshot(view)
        let output = await PageDriver.click(ref: 1, label: "", in: view)
        #expect(output.hasPrefix("Clicked"))
        #expect(await js(view, "window.hit") as? Bool == true)
    }

    @Test func enterHandledByPageSubmitsExactlyOnce() async {
        let view = await page(
            """
            <form onsubmit='window.submits=(window.submits||0)+1;return false'>
            <input aria-label='Query' onkeydown="if(event.key==='Enter'){event.preventDefault();this.form.requestSubmit()}">
            </form>
            """)
        _ = await PageDriver.snapshot(view)
        _ = await PageDriver.type(text: "query", intoField: "", ref: 1, submit: true, in: view)
        #expect(await js(view, "window.submits") as? Int == 1)
    }

    @Test func rejectedFieldValueIsNotReportedAsTypedOrSubmitted() async {
        let view = await page("""
            <form onsubmit='window.submits=(window.submits||0)+1;return false'>
            <input aria-label='Query' oninput="this.value='rejected'">
            </form>
            """)
        _ = await PageDriver.snapshot(view)
        let result = await PageDriver.type(text: "wanted", intoField: "", ref: 1, submit: true, in: view)
        #expect(!result.hasPrefix("Typed"))
        #expect(result.contains("did not retain"))
        #expect(await js(view, "window.submits || 0") as? Int == 0)
    }

    @Test func delayedFieldResetIsVerifiedWithoutRepeatingTheWrite() async {
        let view = await page("""
            <input aria-label='Name' oninput="window.writes=(window.writes||0)+1;setTimeout(()=>this.value='',50)">
            """)
        _ = await PageDriver.snapshot(view)
        let result = await PageDriver.type(text: "Ada", intoField: "", ref: 1, submit: false, in: view)
        #expect(result.contains("did not retain"))
        #expect(result.contains("observationID:"))
        #expect(await js(view, "window.writes") as? Int == 1)
    }

    @Test func fieldsInsideTheirLabelsCanBeFilled() async {
        let view = await page("""
            <form method="post" action="/contact">
            <label>Name <input id="name" name="name"></label>
            <label>Email <input id="email" name="email" type="email"></label>
            <label>Message <textarea id="message" name="message"></textarea></label>
            <button>Send</button></form>
            """)
        let observation = await PageDriver.snapshot(view, lookingFor: "contact form")
        let result = await PageDriver.fillFields([
            .init(ref: 1, value: "Ada Lovelace"), .init(ref: 2, value: "ada@example.com"),
            .init(ref: 3, value: "Is it dimmable?"),
        ], in: view)

        #expect(result.hasPrefix("Filled 3 of 3 fields."), "\(observation)\n\(result)")
    }

    @Test func aFocusableElementIsListedSoItCanBeHovered() async {
        let view = await page("<p>Lamp</p><span id='info' tabindex='0'>Delivery info</span><span tabindex='-1'>Hidden from tab order</span>")

        let output = await PageDriver.snapshot(view)

        #expect(output.contains("button \"Delivery info\""), "\(output)")
        #expect(!output.contains("Hidden from tab order\""))
    }

    @Test func aFocusableContainerIsNotListedAsAButton() async {
        let view = await page("<main tabindex='0'><h1>Lamps</h1><p>Brass and birch.</p></main><div tabindex='0'><a href='#a'>Aster</a></div>")

        let output = await PageDriver.snapshot(view)

        #expect(!output.contains("button \"Lamps"), "\(output)")
        #expect(!output.contains("button \"Aster\""), "\(output)")
        #expect(output.contains("link \"Aster\""), "\(output)")
    }

    @Test func aFileFieldIsListed() async {
        let view = await page("<h1>Send us your report</h1><form method='post' action='/upload'><input type='file' id='file' name='file'><button>Upload</button></form>")

        let output = await PageDriver.snapshot(view, lookingFor: "upload form")

        #expect(output.contains("field \"file\" (file)"), "\(output)")
    }

    @Test func aClickWhoseRefAndLabelDisagreeDoesNothing() async {
        let view = await page("<a href='#' onclick='window.clicked=1'>Home</a><button onclick='window.saved=1'>Save</button>")
        _ = await PageDriver.snapshot(view)

        let refused = await PageDriver.click(ref: 1, label: "Escape key", in: view)
        let agreed = await PageDriver.click(ref: 2, label: "save button", in: view)

        #expect(refused.hasPrefix("[1] is “Home”, not “Escape key”. Nothing was clicked."), "\(refused)")
        #expect(await js(view, "window.clicked") == nil)
        #expect(agreed.hasPrefix("Clicked"), "\(agreed)")
    }

    @Test func typingIntoALinkNamesTheLinkInsteadOfCallingItGone() async {
        let view = await page("<a href='/home'>Home</a><input aria-label='Name'>")
        _ = await PageDriver.snapshot(view)

        let result = await PageDriver.type(text: "Ada", intoField: "", ref: 1, submit: false, in: view)

        #expect(result.hasPrefix("[1] is a link “Home”, not a field."), "\(result)")
    }

    @Test func rejectedSelectionAndEarlierBatchResetsAreNotCountedAsSuccess() async {
        let view = await page("""
            <input aria-label='First'>
            <input aria-label='Second' oninput="document.querySelector('input').value=''">
            <select aria-label='Choice' onchange="this.value='a'"><option value='a'>A</option><option value='b'>B</option></select>
            """)
        _ = await PageDriver.snapshot(view)
        let selection = await PageDriver.selectOption("b", ref: 3, field: "", in: view)
        #expect(!selection.hasPrefix("Selected"))
        let result = await PageDriver.fillFields([
            .init(ref: 1, value: "first"), .init(ref: 2, value: "second"),
        ], in: view)
        #expect(result.hasPrefix("Filled 1 of 2 fields."), "\(result)")
        #expect(result.contains("[1] not verified"))
    }

    @Test func queriesReachDeepTextAndControlPaginationPreservesRefs() async throws {
        let buttons = (1...100).map { "<button>Choice \($0)</button>" }.joined()
        let view = await page("<p>\(String(repeating: "filler ", count: 2000))RareNeedle</p>" + buttons)
        let query = await PageDriver.snapshot(view, lookingFor: "RareNeedle Choice 100")
        #expect(query.contains("RareNeedle"))
        #expect(query.contains("Choice 100"))
        _ = await PageDriver.snapshot(view)
        let page = await PageDriver.snapshot(view, textLimit: 0, controlLimit: 10, controlOffset: 90)
        #expect(page.contains("[100]"))
        let observation = try #require(PageDriver.observation(in: view))
        #expect(!observation.refs.contains(1))
        #expect((await PageDriver.click(ref: 1, label: "", in: view)).hasPrefix("[1] was not listed in that observation."))
    }

    @Test func calendarPaginationRecoversFromRefOffsetsAndChangedQueries() async {
        let controls = (1...13).map { "<button>Control \($0)</button>" }.joined()
        let days = (1...30).map {
            "<div role='gridcell' tabindex='0' style='display:inline-block;width:30px;height:30px' aria-disabled='\($0 < 23)'>\($0)</div>"
        }.joined()
        let view = await page(controls + "<h3>September</h3>" + days)
        let initial = await PageDriver.snapshot(view)
        #expect(initial.contains("button \"29\""))
        let restarted = await PageDriver.snapshot(view, lookingFor: "calendar dates September 29", controlOffset: 140)
        #expect(restarted.contains("button \"29\""))
        #expect(restarted.contains("pagination restarted at 0"))
        let filtered = await PageDriver.snapshot(view, lookingFor: "September calendar controls date 29", controlOffset: 40, viewportOnly: true)
        #expect(filtered.contains("button \"29\""))
        #expect(filtered.contains("pagination restarted at 0"))
        let overflow = await PageDriver.snapshot(view, lookingFor: "September calendar controls date 29", controlOffset: 140, viewportOnly: true)
        #expect(overflow.contains("button \"29\""))
        #expect(overflow.contains("offset exceeds"))
        #expect(overflow.contains("controlOffset=40"))
        let continued = await PageDriver.snapshot(view, lookingFor: "September calendar controls date 29", controlOffset: 40, viewportOnly: true)
        #expect(!continued.contains("pagination restarted"))
        #expect(!continued.contains("button \"29\""))
    }

    @Test func anOffsetCannotHideControlsWhenTheyAllFit() async {
        let view = await page("<a href='/a'>Home</a><a href='/b'>Help</a><select aria-label='Size'><option>Small</option><option>Large</option></select>")
        _ = await PageDriver.snapshot(view)

        let page = await PageDriver.snapshot(view, controlOffset: 2)

        #expect(page.contains("select \"Size"))
        #expect(page.contains("link \"Home\""))
    }

    @Test func aMissingTopicIsReported() async {
        let view = await page("<h1>Welcome</h1><p>New lamps are in.</p><a href='/help'>Help</a>")

        let missing = await PageDriver.snapshot(view, lookingFor: "return policy")
        let present = await PageDriver.snapshot(view, lookingFor: "lamps")

        #expect(missing.contains("“return policy” is not on this page."))
        #expect(!present.contains("is not on this page"))
    }

    @Test func aMenuInsideItsLabelIsNamedByTheLabelAlone() async {
        let view = await page("<label>Delivery <select><option>Standard</option><option>Express</option><option>Next day</option><option>Collect in store</option></select></label>")

        let output = await PageDriver.snapshot(view)

        #expect(output.contains("select \"Delivery\" = \"Standard\" (options: Standard | Express | Next day | Collect in store)"), "\(output)")
    }

    @Test func aMissingTopicNamesTheLinksThatMayLeadThere() async {
        let view = await page("<nav><a href='/'>Home</a> <a href='/lamps'>Lamps</a> <a href='/cart'>Cart</a></nav><h1>Linen Home</h1><p>Lamps and textiles for calm rooms.</p>")

        let output = await PageDriver.snapshot(view, lookingFor: "Aster desk lamp price")

        #expect(output.contains("“Aster desk lamp price” is not on this page. Links that may lead there: [2] “Lamps”."), "\(output)")
    }

    @Test func wordsThatOnlyAppearInLinksAreNotFoundOnThePage() async {
        let view = await page("<nav><a href='/'>Home</a> <a href='/lamps'>Lamps</a></nav><h1>Lamps</h1><ul><li><a href='/a'>Aster desk lamp</a></li><li><a href='/b'>Birch desk lamp</a></li></ul>")

        let output = await PageDriver.snapshot(view, lookingFor: "Aster desk lamp price")

        #expect(output.contains("Links that may lead there: [3] “Aster desk lamp”, [4] “Birch desk lamp”"), "\(output)")
    }

    @Test func aWrongKindOfControlNamesTheToolForIt() async {
        let view = await page("<input aria-label='Name'><button>Confirm booking</button>")
        _ = await PageDriver.snapshot(view)

        let output = await PageDriver.type(text: "", intoField: "Confirm booking", ref: 2, submit: true, in: view)

        #expect(output.contains("To use it, call clickOnPage with ref 2."), "\(output)")
    }

    @Test func aWrongRefForANamedFieldPointsToThatField() async {
        let view = await page("<a href='/lamps'>Lamps</a><label>City <input></label>")
        _ = await PageDriver.snapshot(view)

        let output = await PageDriver.type(text: "Lviv", intoField: "City", ref: 1, submit: false, in: view)

        #expect(output.contains("“City” is [2]: use ref 2."), "\(output)")
        #expect(!output.contains("clickOnPage"), "\(output)")
    }

    @Test func aTopicNotYetShownOnALongPagePointsToScrolling() async {
        let view = await page("<h1>Journal</h1><div style='height:5000px'></div><div id='promo'></div>")

        let output = await PageDriver.snapshot(view, lookingFor: "promo code")

        #expect(output.contains("“promo code” is not on the page yet. More of the page is below; use scrollPage to see it."), "\(output)")
    }

    @Test func embeddedPagesAreReported() async {
        let view = await page("<p>Your booking is below.</p><iframe srcdoc='<p>Code BK-1</p>'></iframe>")

        let output = await PageDriver.snapshot(view, lookingFor: "confirmation code")

        #expect(output.contains("This page has 1 embedded page. Use listFrames and readFrame"))
        #expect(!output.contains("is not on this page"))
    }

    @Test func labelActionsRejectObservationsFromThePreviousDocument() async throws {
        let view = await page("<button>29</button>")
        _ = await PageDriver.snapshot(view)
        let before = try #require(PageDriver.observation(in: view))
        view.loadHTMLString("<button onclick='window.hit=true'>29</button>", baseURL: nil)
        #expect(await PageSettle.untilIdle(view, timeout: .seconds(20)))
        let result = await PageDriver.$expectedObservation.withValue(before.id) {
            await PageDriver.click(ref: 0, label: "29", in: view)
        }
        #expect(result == PageDriver.staleMessage)
        #expect(await js(view, "window.hit === undefined") as? Bool == true)
    }

    @Test func compactBudgetAppliesAfterActionsIncludingLongOptions() async {
        let options = (1...80).map { "<option>Option \($0) \(String(repeating: "&amp;", count: 80))</option>" }.joined()
        let view = await page(
            "<button>Ordinary action</button><select aria-label='Options'>\(options)</select>" + String(repeating: "<p>Text and details</p>", count: 100))
        await PageDriver.$outputBudget.withValue(.init(textCharacters: 800, controls: 12, totalCharacters: 2000)) {
            _ = await PageDriver.snapshot(view)
            let output = await PageDriver.click(ref: 1, label: "", in: view)
            #expect(AgentToolkit.untrusted(output).utf8.count <= 2000)
            #expect(output.contains("observationID:"))
        }
    }

    @Test func compactQueriesKeepTheMatchWithMultibyteText() async {
        let view = await page("<p>\(String(repeating: "文🙂", count: 2000))重要な結果</p>")
        await PageDriver.$outputBudget.withValue(.init(textCharacters: 800, controls: 12, totalCharacters: 2000)) {
            let output = await PageDriver.snapshot(view, lookingFor: "重要な結果")
            #expect(output.contains("重要な結果"))
            #expect(AgentToolkit.untrusted(output).utf8.count <= 2000)
        }
    }

    @Test func longSelectedLabelsStayInsideTheCompactBudget() async {
        let view = await page("<select aria-label='Choices'><option>A</option><option value='chosen'>\(String(repeating: "&amp;", count: 2000))</option></select>")
        await PageDriver.$outputBudget.withValue(.init(textCharacters: 800, controls: 12, totalCharacters: 2000)) {
            _ = await PageDriver.snapshot(view)
            let output = await PageDriver.selectOption("chosen", ref: 1, field: "", in: view)
            #expect(output.hasPrefix("Selected"), "\(output)")
            #expect(AgentToolkit.untrusted(output).utf8.count <= 2000)
        }
    }

    @Test func batchingWaitsForNavigationOnceAndReturnsOneObservation() async {
        let view = await page((1...8).map { "<input aria-label='Field \($0)'>" }.joined())
        _ = await PageDriver.snapshot(view)
        var interactionWaits = 0
        await PageSettle.$interactionObserver.withValue({ interactionWaits += 1 }) {
            for ref in 1...8 {
                let result = await PageDriver.type(text: "individual", intoField: "", ref: ref, submit: false, in: view)
                #expect(result.hasPrefix("Typed"), "\(result)")
            }
        }
        #expect(interactionWaits == 8)
        interactionWaits = 0
        let batch = await PageSettle.$interactionObserver.withValue({ interactionWaits += 1 }) {
            await PageDriver.fillFields((1...8).map { .init(ref: $0, value: "batch") }, in: view)
        }
        #expect(batch.hasPrefix("Filled 8 of 8"))
        #expect(batch.components(separatedBy: "observationID:").count == 2)
        #expect(interactionWaits == 1)
        #expect(await js(view, "Array.from(document.querySelectorAll('input')).every(input => input.value === 'batch')") as? Bool == true)
    }

    @Test func checkedStateIsIdempotentAndDropdownInspectionContinues() async {
        let options = (1...40).map { "<option>Option \($0)</option>" }.joined()
        let view = await page(
            "<input type='checkbox' aria-label='Remember' onchange='window.changes=(window.changes||0)+1'><select aria-label='Choices'>\(options)</select>")
        _ = await PageDriver.snapshot(view)
        #expect((await PageDriver.setChecked(ref: 1, checked: true, in: view)).hasPrefix("Set checked"))
        #expect((await PageDriver.setChecked(ref: 1, checked: true, in: view)).hasPrefix("Checked state"))
        #expect(await js(view, "window.changes") as? Int == 1)
        let inspected = await PageDriver.inspectControl(ref: 2, offset: 20, in: view)
        #expect(inspected.contains("Option 21"))
        #expect(inspected.contains("nextOffset"))
    }

    @Test func checkedPostconditionUsesTheRefreshedExecutionScope() async throws {
        let view = await page("<input type='checkbox' aria-label='Remember'>")
        _ = await PageDriver.snapshot(view)
        let prior = try #require(PageDriver.observation(in: view))
        let scope = PageAutomationGuard(documentURL: prior.url, snapshot: prior.id, validate: { true })
        let output = await PageAutomationGuard.$current.withValue(scope) {
            await PageDriver.$expectedObservation.withValue(prior.id) {
                await PageDriver.setChecked(ref: 1, checked: true, in: view)
            }
        }
        #expect(output.hasPrefix("Set checked state to true."), "\(output)")
        #expect(PageDriver.observation(in: view)?.id != prior.id)
    }

    @Test func waitsForAsyncTextAndReportsTimeout() async {
        let view = await page("<p id='status'>Pending</p>")
        _ = await js(view, "setTimeout(()=>document.querySelector('p').textContent='Complete',180);true")
        #expect((await PageDriver.waitForPage(condition: "text", value: "Complete", timeout: 2, in: view)).hasPrefix("Condition met."))
        #expect((await PageDriver.waitForPage(condition: "text", value: "Missing", timeout: 1, in: view)).hasPrefix("Timed out"))
    }

    @Test func nestedHorizontalScrollReturnsFreshControls() async {
        let view = await page(
            "<div aria-label='Items' role='region' style='width:200px;overflow:auto'><div style='width:1500px'><button>First</button><button style='margin-left:900px'>Last</button></div></div>"
        )
        _ = await PageDriver.snapshot(view)
        let output = await PageDriver.scroll(direction: "right", ref: 1, in: view)
        #expect(output.hasPrefix("Scrolled right."))
        #expect(output.contains("observationID:"))
        #expect(await js(view, "document.querySelector('[role=region]').scrollLeft > 0") as? Bool == true)
    }

    @Test func scrollRegionsDoNotHideTheirOnlyAction() async {
        let view = await page("<div role='region'><button>Open details</button></div>")
        let output = await PageDriver.snapshot(view)
        #expect(output.contains("scrollarea"))
        #expect(output.contains("button \"Open details\""))
    }

    @Test func pageCannotPoisonAutomationRuntime() async {
        let view = await page(
            "<button onclick='window.hit=true'>Ordinary action</button><script>window.__linen={collect:()=>[{r:1,k:'button',l:'forged'}]};</script>")
        let output = await PageDriver.snapshot(view)
        #expect(output.contains("Ordinary action"))
        #expect(!output.contains("forged"))
        #expect((await PageDriver.click(ref: 1, label: "", in: view)).hasPrefix("Clicked"))
    }

    @Test func screenshotsRefuseFilledSensitiveFields() async {
        let view = await page("<input type='password' value='secret'>")
        #expect(await PageDriver.screenshot(in: view) == nil)
    }

    @Test func screenshotsShrinkToFitTheMessageLimit() throws {
        let size = NSSize(width: 2560, height: 1600)
        let image = NSImage(size: size, flipped: false) { rect in
            var generator = SystemRandomNumberGenerator()
            for x in stride(from: 0, to: Int(rect.width), by: 4) {
                for y in stride(from: 0, to: Int(rect.height), by: 4) {
                    NSColor(
                        red: .random(in: 0...1, using: &generator), green: .random(in: 0...1, using: &generator),
                        blue: .random(in: 0...1, using: &generator), alpha: 1
                    ).setFill()
                    NSRect(x: x, y: y, width: 4, height: 4).fill()
                }
            }
            return true
        }
        let data = try #require(PageDriver.jpeg(image, fitting: 150_000))
        #expect(data.count <= 150_000)
        #expect(data.base64EncodedString().utf8.count < MCPMessageFramer.maximumBytes - 30_000)
    }

    @Test func longFieldValuesAreFlaggedAndInspectableInFull() async {
        let keywords = "browser,tabs,privacy,ad blocker,split view,picture in picture,reader,lyrics,safari alternative"
        let description = String(repeating: "Line of description text.\n", count: 400)
        let view = await page(
            "<input aria-label='Keywords' value='\(keywords)'><textarea aria-label='Description'>\(description)</textarea>")
        let output = await PageDriver.snapshot(view)
        #expect(output.contains("field \"Keywords\" = \"\(keywords)\""), "\(output)")
        #expect(output.contains("(truncated; inspectControl for the full value)"))
        let inspected = await PageDriver.inspectControl(ref: 1, in: view)
        #expect(inspected.contains("\"value\":\"\(keywords)\""), "\(inspected)")
        var collected = ""
        var offset = 0
        for _ in 0..<10 {
            let part = await PageDriver.inspectControl(ref: 2, offset: offset, in: view)
            let json = try? JSONSerialization.jsonObject(with: Data(part.split(separator: "\n")[1].utf8)) as? [String: Any]
            collected += json?["value"] as? String ?? ""
            guard let next = json?["nextOffset"] as? Int else { break }
            offset = next
        }
        #expect(collected == description)
    }

    @Test func scopeCoversEveryMatchingElement() async {
        let view = await page(
            "<input type='hidden' name='token'><button>Outside</button><section><input aria-label='First'></section><section><textarea aria-label='Second'></textarea></section>")
        let sections = await PageDriver.snapshot(view, scope: "section")
        #expect(sections.contains("\"First\"") && sections.contains("\"Second\""), "\(sections)")
        #expect(!sections.contains("button \"Outside\""))
        let fields = await PageDriver.snapshot(view, scope: "textarea, input")
        #expect(fields.contains("\"First\"") && fields.contains("\"Second\""), "\(fields)")
        #expect((await PageDriver.snapshot(view, scope: "article")) == "No element matches that scope.")
    }

    @Test func actionsReportTextTheyRevealed() async {
        let filler = String(repeating: "<p>Unchanged paragraph of page content.</p>", count: 120)
        let view = await page(
            "<button onclick=\"document.body.insertAdjacentHTML('beforeend', '<p>A description of your app.</p>')\">More information</button>\(filler)")
        let first = await PageDriver.snapshot(view)
        #expect(!first.contains("NEW ON PAGE:"))
        let clicked = await PageDriver.click(ref: 1, label: "", in: view)
        #expect(clicked.contains("NEW ON PAGE:\nA description of your app."), "\(clicked)")
        #expect(!(await PageDriver.snapshot(view)).contains("NEW ON PAGE:"))
    }

    @Test func unlistedRefsAreNotReportedAsStale() async {
        let view = await page("<nav><a href='#a'>Home</a></nav><main><button>Help</button></main>")
        _ = await PageDriver.snapshot(view, scope: "nav")
        let output = await PageDriver.click(ref: 2, label: "", in: view)
        #expect(output.hasPrefix("[2] was not listed in that observation."), "\(output)")
    }

    @Test func sensitiveEditableTextIsRedactedAndCannotBeOverwritten() async {
        let view = await page("<div contenteditable='true' aria-label='Recovery phrase'>hidden-recovery-words</div>")
        let output = await PageDriver.snapshot(view)
        #expect(!output.contains("hidden-recovery-words"))
        #expect(output.contains("filled, hidden"))
        #expect(!(await PageDriver.type(text: "replacement", intoField: "", ref: 1, submit: false, in: view)).hasPrefix("Typed"))
        #expect(await PageDriver.screenshot(in: view) == nil)
    }

    @Test func hoverHandlersAndNativeKeyboardReachWebKit() async {
        let view = await page(
            """
            <style>#hover:hover + #revealed { display:block } #revealed { display:none }</style>
            <button id='hover' onmouseenter="document.querySelector('#revealed').style.display='block'">Reveal</button><p id='revealed'>Hover details</p>
            <input aria-label='Input' onkeydown='window.lastKey=event.key'>
            """)
        let window = NSWindow(
            contentRect: NSRect(x: 50, y: 50, width: 500, height: 400),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderBack(nil)
        defer {
            window.contentView = nil
            window.close()
        }
        _ = await PageDriver.snapshot(view)
        let hover = await PageDriver.hover(ref: 1, in: view)
        #expect(hover.contains("Hover details"), "\(hover)")
        #expect(hover.contains("CSS-only hover is unavailable"))
        let key = await PageDriver.pressKey("ArrowDown", ref: 2, in: view)
        #expect(key.hasPrefix("Sent ArrowDown"), "\(key)")
        #expect(await js(view, "window.lastKey") as? String == "ArrowDown")
        #expect(await PageDriver.screenshot(in: view) != nil)
    }
}
