// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
struct AgentRequestConstraintsTests {
    @Test func aBanOnSendingRefusesEverySubmission() {
        let constraints = AgentRequestConstraints(request: "Fill in the contact form with my name. Do not send it.")

        #expect(constraints.refusal(clicking: "Send", submits: true) != nil)
        #expect(constraints.refusal(clicking: "Upload", submits: true) != nil)
        #expect(constraints.refusal(clicking: "Help", submits: false) == nil)
        #expect(constraints.submissionRefusal != nil)
    }

    @Test func aBanOnSendingRefusesAScriptedSendButton() {
        let constraints = AgentRequestConstraints(request: "Draft a reply but don't send it.")

        #expect(constraints.refusal(clicking: "Send", submits: false) != nil)
        #expect(constraints.refusal(clicking: "Send now", submits: false) != nil)
        #expect(constraints.refusal(clicking: "Sender details", submits: false) == nil)
    }

    @Test func aBannedVerbMatchesWholeWordsOnly() {
        let constraints = AgentRequestConstraints(request: "Don't add anything, just check the address.")

        #expect(constraints.refusal(clicking: "Add to cart", submits: false) != nil)
        #expect(constraints.refusal(clicking: "Edit address", submits: false) == nil)
        #expect(constraints.refusal(clicking: "Paddle boards", submits: false) == nil)
    }

    @Test func aBanOnOneActionRefusesOnlyThatControl() {
        let constraints = AgentRequestConstraints(request: "Add the Birch lamp to my cart, but don't check out.")

        #expect(constraints.refusal(clicking: "Checkout", submits: true) != nil)
        #expect(constraints.refusal(clicking: "Check out now", submits: false) != nil)
        #expect(constraints.refusal(clicking: "Add to cart", submits: true) == nil)
        #expect(constraints.submissionRefusal == nil)
    }

    @Test func gerundsAndPhrasingVariantsAreRecognised() {
        #expect(AgentRequestConstraints(request: "Attach the file without submitting the form.").submissionRefusal != nil)
        #expect(AgentRequestConstraints(request: "Set the colour. Do not place an order.").refusal(clicking: "Place order", submits: true) != nil)
        #expect(AgentRequestConstraints(request: "Don’t buy anything").refusal(clicking: "Buy now", submits: false) != nil)
    }

    @Test func ordinaryRequestsAndHarmlessNegativesConstrainNothing() {
        #expect(AgentRequestConstraints(request: "Send the form for me").refusal(clicking: "Send", submits: true) == nil)
        #expect(AgentRequestConstraints(request: "Don't worry about the price, just save it").refusal(clicking: "Save", submits: true) == nil)
    }

    @Test func checkingOutNeedsARequestToBuy() {
        let browsing = AgentRequestConstraints(request: "Add two lamps to the cart, then tell me the total.")
        #expect(browsing.refusal(clicking: "Check out", submits: true)?.hasPrefix(AgentRequestConstraints.purchaseRefusalPrefix) == true)
        #expect(browsing.refusal(clicking: "Place order", submits: true) != nil)
        #expect(browsing.refusal(clicking: "Add to cart", submits: true) == nil)
        #expect(AgentRequestConstraints(request: "Buy the Aster lamp").refusal(clicking: "Check out", submits: true) == nil)
        #expect(AgentRequestConstraints.none.refusal(clicking: "Checkout", submits: true) == nil)
        #expect(browsing.refusal(clicking: "Buy", submits: false, isLink: true) == nil)
        #expect(AgentRequestConstraints(request: "Add the lamp, but don't check out").refusal(clicking: "Checkout", submits: false, isLink: true) != nil)
    }

    @Test func aComparisonAnswerMustCoverBothSides() {
        let request = AgentRequestConstraints(request: "Which is cheaper on this shop, the Aster or the Birch desk lamp? Tell me its price.")

        #expect(request.alternatives == ["aster", "birch"])
        #expect(request.incompleteAnswer("The Aster desk lamp costs $129.")?.contains("Check Birch too") == true)
        #expect(request.incompleteAnswer("The Aster desk lamp costs $129.", earlier: "Birch desk lamp\nPrice $99")?.contains("Price $99") == true)
        #expect(request.incompleteAnswer("The Birch lamp is cheaper than the Aster, at $99.") == nil)
        #expect(request.incompleteAnswer("Birch is cheaper, at $99.") == nil)
        #expect(AgentRequestConstraints(request: "Is it red or blue?").alternatives.isEmpty)
    }

    @Test func aPreferenceOnlyTheUserKnowsIsNamed() {
        #expect(AgentRequestConstraints(request: "Set the lamp to my usual colour.").preference == "my usual colour")
        #expect(AgentRequestConstraints(request: "Set the lamp to Brass.").preference == nil)
    }

    @Test func aRefusedClickDoesNotPressTheButton() async {
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: WebViewPool.makeConfiguration())
        view.loadHTMLString("<form onsubmit='window.sent=1;return false'><input aria-label='Name'><button>Send</button></form>", baseURL: nil)
        let listed = await waitUntil { await PageDriver.snapshot(view).contains("[2] button \"Send\"") }
        #expect(listed, "The form never appeared in a snapshot")

        let refused = await PageDriver.click(ref: 2, label: "Send", in: view, constraints: AgentRequestConstraints(request: "Do not send it."))
        let typed = await PageDriver.type(text: "Ada", intoField: "", ref: 1, submit: true, in: view,
                                          constraints: AgentRequestConstraints(request: "Do not send it."))

        #expect(refused.hasPrefix("The user asked you not to send."), "\(refused)")
        #expect(typed.hasPrefix("The user asked you not to send."), "\(typed)")
        #expect((try? await view.evaluateJavaScript("window.sent")) == nil)
    }

    @Test func aContinuedTaskKeepsTheRequestAndTheAnswers() {
        let toolkit = AgentToolkit(browser: BrowserModel(database: .temporary()), media: MediaCenter(), log: ConversationLog(database: .temporary()))
        toolkit.beginTask(AgentTaskContext(id: UUID(), tabID: UUID(), isContinuation: true))
        toolkit.resumeRequest("Fill in the form but don't send it.", answers: ["Size 9"])

        #expect(toolkit.requestConstraints.refusal(clicking: "Send", submits: false) != nil)
        #expect(toolkit.turn.userWords == ["Fill in the form but don't send it.", "Size 9"])
        #expect(toolkit.turn.askedUser)
    }

    @Test func aPreferenceIsRemindedOnceBeforeTheFirstChange() {
        let toolkit = AgentToolkit(browser: BrowserModel(database: .temporary()), media: MediaCenter(), log: ConversationLog(database: .temporary()))
        toolkit.beginTask(AgentTaskContext(id: UUID(), tabID: UUID()))
        toolkit.requestConstraints = AgentRequestConstraints(request: "Set the lamp to my usual colour.")

        #expect(toolkit.preferenceRefusal(for: "readPage") == nil)
        #expect(toolkit.preferenceRefusal(for: "selectOption")?.contains("my usual colour") == true)
        #expect(toolkit.preferenceRefusal(for: "selectOption") == nil)
    }
}
