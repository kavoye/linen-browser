// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
struct ContactAutofillScriptTests {
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
        configuration.userContentController.add(sink, contentWorld: ContactAutofill.world, name: "linenContactAutofill")
        configuration.userContentController.addUserScript(WKUserScript(
            source: ContactAutofillScript.source, injectionTime: .atDocumentStart,
            forMainFrameOnly: false, in: ContactAutofill.world
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
            in: nil, contentWorld: ContactAutofill.world
        )
        #expect(await waitUntil { sink.body?["token"] is String })
        return try #require(sink.body?["token"] as? String)
    }

    private func fill(_ token: String, in view: WKWebView, url: String = "https://checkout.example/") async throws -> Int {
        let result = try await view.callAsyncJavaScript(
            "return globalThis.__linenContactAutofill.fill(token, url, contact);",
            arguments: ["token": token, "url": url,
                        "contact": ["name": "Ada Example", "given-name": "Ada", "family-name": "Example",
                                    "email": "ada@example.test", "tel": "+44 1234 567890", "address-line1": "123 Example Street",
                                    "street-address": "123 Example Street\nFlat 4", "country": "GB", "country-name": "United Kingdom",
                                    "postal-code": "AB1 2CD",
                                   ],
                       ],
            in: nil, contentWorld: ContactAutofill.world
        )
        return try #require(result as? Int)
    }

    @Test(.boundedWebViews) func fillsShippingWithoutChangingBillingExistingTextOrSensitiveFields() async throws {
        let (view, sink) = try await load(#"""
        <form onsubmit="window.submitted=true; return false">
          <input id="first" autocomplete="shipping given-name">
          <input id="last" autocomplete="shipping family-name">
          <input id="email" autocomplete="shipping email" value="keep@example.test">
          <textarea id="street" autocomplete="shipping street-address"></textarea>
          <select id="country" autocomplete="shipping country"><option value="">Choose</option><option value="GB">United Kingdom</option></select>
          <input id="billing" autocomplete="billing given-name">
          <input id="hidden" autocomplete="shipping name" style="opacity:0">
          <input id="password" type="password" autocomplete="shipping name">
          <input id="card" autocomplete="cc-name">
        </form>
        <form><input id="other" autocomplete="shipping given-name"></form>
        <script>window.events=[]; document.addEventListener('input', e => events.push(e.target.id));</script>
        """#)
        let token = try await select("first", in: view, sink: sink)
        #expect(try await fill(token, in: view) == 4)
        #expect(try await view.evaluateJavaScript("first.value") as? String == "Ada")
        #expect(try await view.evaluateJavaScript("last.value") as? String == "Example")
        #expect(try await view.evaluateJavaScript("street.value") as? String == "123 Example Street\nFlat 4")
        #expect(try await view.evaluateJavaScript("country.value") as? String == "GB")
        #expect(try await view.evaluateJavaScript("email.value") as? String == "keep@example.test")
        #expect(try await view.evaluateJavaScript("billing.value + hidden.value + password.value + card.value + other.value") as? String == "")
        #expect(try await view.evaluateJavaScript("!!window.submitted") as? Bool == false)
        #expect(try await view.evaluateJavaScript("events.join(',')") as? String == "first,last,street,country")
        let observation = await PageDriver.readRenderedPage(view)
        #expect(!observation.contains("123 Example Street"))
        #expect(!observation.contains("= Ada"))
        #expect(try await fill(token, in: view) == 0)
    }

    @Test(.boundedWebViews) func respectsAutocompleteOffAndSectionsAndSupportsCommonLabels() async throws {
        let (view, sink) = try await load(#"""
        <form><input id="first_name"><input id="phone" type="tel"><input id="postcode">
        <input id="email" autocomplete="off" type="email"><input id="login" autocomplete="username">
        <input id="other" autocomplete="section-other name"><input id="search" placeholder="Search email">
        </form>
        """#)
        let token = try await select("first_name", in: view, sink: sink)
        #expect(try await fill(token, in: view) == 3)
        #expect(try await view.evaluateJavaScript("phone.value") as? String == "+44 1234 567890")
        #expect(try await view.evaluateJavaScript("postcode.value") as? String == "AB1 2CD")
        #expect(try await view.evaluateJavaScript("email.value + login.value + other.value + search.value") as? String == "")
    }

    @Test(.boundedWebViews) func rejectsChangedPageReplacedFieldAndForgedSelection() async throws {
        let (view, sink) = try await load(#"<input id="first" autocomplete="given-name">"#)
        #expect(try await view.evaluateJavaScript("typeof globalThis.__linenContactAutofill") as? String == "undefined")
        _ = try await view.evaluateJavaScript("first.dispatchEvent(new FocusEvent('focusin', {bubbles:true}));")
        #expect(sink.body == nil)
        #expect(try await fill(UUID().uuidString, in: view) == 0)
        let token = try await select("first", in: view, sink: sink)
        _ = try await view.evaluateJavaScript("history.pushState({}, '', '/changed');")
        #expect(try await fill(token, in: view) == 0)
        _ = try await view.evaluateJavaScript("history.replaceState({}, '', '/'); first.outerHTML=first.outerHTML;")
        #expect(try await fill(token, in: view) == 0)
    }

    @Test(.boundedWebViews) func loginFieldsDoNotOfferContactSuggestions() async throws {
        let (view, sink) = try await load(#"<form><input id="email" type="email"><input id="password" type="password"></form>"#)
        _ = try await view.evaluateJavaScript("email.focus();")
        #expect(sink.body?["token"] as? String == nil)
        _ = try await view.evaluateJavaScript("password.focus();")
        #expect(sink.body?["token"] as? String == nil)
        #expect(try await fill(UUID().uuidString, in: view) == 0)
    }

    @Test(.boundedWebViews) func writingPromptsDoNotOfferContactSuggestions() async throws {
        let (view, sink) = try await load(#"""
        <textarea id="prompt" placeholder="Write a polite rejection email"></textarea>
        <textarea id="address" placeholder="Shipping address"></textarea>
        """#)
        _ = try await view.evaluateJavaScript("document.getElementById('prompt').focus();")
        #expect(sink.body?["token"] as? String == nil)
        let token = try await select("address", in: view, sink: sink)
        #expect(try await fill(token, in: view) == 1)
        #expect(try await view.evaluateJavaScript("address.value") as? String == "123 Example Street\nFlat 4")
    }
}
