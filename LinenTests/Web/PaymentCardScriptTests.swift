// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
struct PaymentCardScriptTests {
    private final class Sink: NSObject, WKScriptMessageHandler {
        var body: [String: Any]?

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            body = message.body as? [String: Any]
        }
    }

    private func load(_ html: String) async throws -> (WKWebView, Sink) {
        let configuration = WebViewPool.makeConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let sink = Sink()
        configuration.userContentController.add(sink, contentWorld: PaymentCardAutofill.world, name: "linenCardAutofill")
        configuration.userContentController.addUserScript(WKUserScript(
            source: PaymentCardScript.source, injectionTime: .atDocumentStart,
            forMainFrameOnly: false, in: PaymentCardAutofill.world
        ))
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        view.loadHTMLString("<!doctype html>" + html, baseURL: URL(string: "https://checkout.example/"))
        #expect(await PageSettle.untilIdle(view, timeout: .seconds(20)))
        return (view, sink)
    }

    private func select(_ id: String, in view: WKWebView, sink: Sink) async throws -> String {
        sink.body = nil
        _ = try await view.callAsyncJavaScript(
            "document.getElementById(id).focus();", arguments: ["id": id],
            in: nil, contentWorld: PaymentCardAutofill.world
        )
        #expect(await waitUntil { sink.body?["token"] is String })
        return try #require(sink.body?["token"] as? String)
    }

    private func fill(_ token: String, in view: WKWebView, url: String = "https://checkout.example/") async throws -> Int {
        let result = try await view.callAsyncJavaScript(
            "return globalThis.__linenCardAutofill.fill(token, url, card);",
            arguments: ["token": token, "url": url,
                        "card": ["number": "4242424242424242", "cardholder": "Ada Example", "month": 9, "year": 2030],
                       ],
            in: nil, contentWorld: PaymentCardAutofill.world
        )
        return try #require(result as? Int)
    }

    @Test(.boundedWebViews) func fillsOnlyTheSelectedFormAndSectionWithoutSecurityCodesOrSubmission() async throws {
        let (view, sink) = try await load(#"""
        <form id="first" onsubmit="window.submitted=true; return false">
          <input id="number" autocomplete="section-a cc-number">
          <input id="name" autocomplete="section-a cc-name">
          <select id="month" autocomplete="section-a cc-exp-month"><option value="">Month</option><option value="9">September</option></select>
          <select id="year" autocomplete="section-a cc-exp-year"><option value="">Year</option><option value="30">2030</option></select>
          <input id="cvv" autocomplete="cc-csc">
          <input id="hidden" autocomplete="section-a cc-number" style="opacity:0">
          <input id="otherSection" autocomplete="section-b cc-number">
        </form>
        <form><input id="otherForm" autocomplete="cc-number"></form>
        <script>window.events=[]; document.addEventListener('input', e => events.push(e.target.id));</script>
        """#)
        let token = try await select("number", in: view, sink: sink)
        #expect(try await fill(token, in: view) == 4)
        let result = try await view.evaluateJavaScript(#"""
        JSON.stringify({number:number.value,name:document.getElementById('name').value,month:month.value,year:year.value,
                        cvv:cvv.value,hidden:hidden.value,otherSection:otherSection.value,otherForm:otherForm.value,
                        submitted:!!window.submitted,events:events,marked:number.hasAttribute('data-linen-payment-card')})
        """#) as? String
        let data = try #require(result?.data(using: .utf8))
        let fields = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(fields["number"] as? String == "4242424242424242")
        #expect(fields["name"] as? String == "Ada Example")
        #expect(fields["month"] as? String == "9")
        #expect(fields["year"] as? String == "30")
        for id in ["cvv", "hidden", "otherSection", "otherForm"] { #expect(fields[id] as? String == "") }
        #expect(fields["submitted"] as? Bool == false)
        #expect(fields["marked"] as? Bool == true)
        #expect(fields["events"] as? [String] == ["number", "name", "month", "year"])
        let observation = await PageDriver.readRenderedPage(view)
        #expect(!observation.contains("4242424242424242"))
        #expect(!observation.contains("Ada Example"))
        #expect(observation.contains("select \"month\" = (filled, hidden)"))
        let refused = await PageDriver.selectOption("2030", ref: 0, field: "year", in: view)
        #expect(refused.contains("sensitive"))
        #expect(try await fill(token, in: view) == 0)
    }

    @Test(.boundedWebViews) func refusesAChangedURLOrReplacedField() async throws {
        let (view, sink) = try await load(#"<input id="number" autocomplete="cc-number">"#)
        let token = try await select("number", in: view, sink: sink)
        _ = try await view.evaluateJavaScript("history.pushState({}, '', '/changed');")
        #expect(try await fill(token, in: view) == 0)
        _ = try await view.evaluateJavaScript("history.replaceState({}, '', '/'); number.outerHTML = number.outerHTML;")
        #expect(try await fill(token, in: view) == 0)
        #expect(try await view.evaluateJavaScript("number.value") as? String == "")
    }

    @Test(.boundedWebViews) func supportsUnlabelledCardFieldsAndShortExpiry() async throws {
        let (view, sink) = try await load(#"""
        <form><input id="card_number"><input id="expiry" placeholder="MM/YY" maxlength="5">
        <input id="cvc" name="card_security_code"><input id="secret" type="password" autocomplete="cc-number"></form>
        """#)
        let token = try await select("card_number", in: view, sink: sink)
        #expect(try await fill(token, in: view) == 2)
        #expect(try await view.evaluateJavaScript("expiry.value") as? String == "09/30")
        #expect(try await view.evaluateJavaScript("cvc.value + secret.value") as? String == "")
    }

    @Test(.boundedWebViews) func pageScriptsCannotAccessTheFillingBridgeOrForgeSelection() async throws {
        let (view, sink) = try await load(#"<input id="number" autocomplete="cc-number">"#)
        #expect(try await view.evaluateJavaScript("typeof globalThis.__linenCardAutofill") as? String == "undefined")
        _ = try await view.evaluateJavaScript("number.dispatchEvent(new FocusEvent('focusin', { bubbles:true }));")
        #expect(sink.body == nil)
        #expect(try await fill(UUID().uuidString, in: view) == 0)
    }

    @Test func onlyUnambiguousHTTPSOriginsQualify() {
        for url in ["http://checkout.example/", "file:///checkout.html", "about:blank", "https://user@checkout.example/"] {
            #expect(!PaymentCardAutofill.isSecure(URL(string: url)!))
        }
        #expect(PaymentCardAutofill.isSecure(URL(string: "https://checkout.example:8443/pay")!))
    }
}
