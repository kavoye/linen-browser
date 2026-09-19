// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
struct PasswordAutofillScriptTests {
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
        configuration.userContentController.add(sink, contentWorld: PasswordAutofill.world, name: "linenPasswords")
        configuration.userContentController.addUserScript(WKUserScript(
            source: PasswordAutofillScript.source, injectionTime: .atDocumentStart,
            forMainFrameOnly: false, in: PasswordAutofill.world
        ))
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        view.loadHTMLString("<!doctype html>" + html, baseURL: URL(string: "https://login.example/"))
        #expect(await PageSettle.untilIdle(view, timeout: .seconds(20)))
        _ = try await view.callAsyncJavaScript("globalThis.__linenPasswords.setEnabled(true);", arguments: [:], in: nil, contentWorld: PasswordAutofill.world)
        sink.body = nil
        return (view, sink)
    }

    private func select(in view: WKWebView, sink: Sink) async throws -> String {
        _ = try await view.callAsyncJavaScript("document.getElementById('password').focus();", arguments: [:], in: nil, contentWorld: PasswordAutofill.world)
        #expect(await waitUntil { sink.body?["token"] is String })
        return try #require(sink.body?["token"] as? String)
    }

    private func fill(_ token: String, in view: WKWebView) async throws -> Int {
        let result = try await view.callAsyncJavaScript(
            "return globalThis.__linenPasswords.fill(token,url,login);",
            arguments: ["token": token, "url": "https://login.example/", "login": ["username": "ada@example.test", "password": "dummy-secret"]],
            in: nil, contentWorld: PasswordAutofill.world
        )
        return try #require(result as? Int)
    }

    @Test(.boundedWebViews) func fillsOnlyLoginFieldsRedactsTheirValuesAndDoesNotSubmit() async throws {
        let (view, sink) = try await load(#"""
        <form onsubmit="window.submitted=true; return false">
        <input id="username" autocomplete="username"><input id="password" type="password" autocomplete="current-password">
        <input id="hidden" type="password" style="display:none"><input id="code" autocomplete="one-time-code">
        </form><form><input id="other" type="password"></form>
        """#)
        let token = try await select(in: view, sink: sink)
        #expect(try await fill(token, in: view) == 2)
        #expect(try await view.evaluateJavaScript("username.value") as? String == "ada@example.test")
        #expect(try await view.evaluateJavaScript("password.value") as? String == "dummy-secret")
        #expect(try await view.evaluateJavaScript("hidden.value+code.value+other.value") as? String == "")
        #expect(try await view.evaluateJavaScript("!!window.submitted") as? Bool == false)
        let observation = await PageDriver.readRenderedPage(view)
        #expect(!observation.contains("dummy-secret"))
        #expect(!observation.contains("ada@example.test"))
        #expect(try await fill(token, in: view) == 0)
    }

    @Test(.boundedWebViews) func neverOffersSavedLoginsForRegistration() async throws {
        let (view, sink) = try await load(#"""
        <form><input id="username" autocomplete="username" value="ada">
        <input id="password" type="password" autocomplete="new-password" value="new-secret">
        <input id="confirmation" type="password" autocomplete="new-password" value="different"></form>
        """#)
        _ = try await view.callAsyncJavaScript("password.focus();", arguments: [:], in: nil, contentWorld: PasswordAutofill.world)
        #expect(sink.body?["token"] as? String == nil)
        #expect(try await fill(UUID().uuidString, in: view) == 0)
    }

    @Test(.boundedWebViews) func refusesChangedURLAndPageCannotAccessBridgeOrForgeSave() async throws {
        let (view, sink) = try await load(#"""
        <form id="form"><input id="username" autocomplete="username"><input id="password" type="password"></form>
        """#)
        #expect(try await view.evaluateJavaScript("typeof globalThis.__linenPasswords") as? String == "undefined")
        _ = try await view.evaluateJavaScript("form.dispatchEvent(new SubmitEvent('submit', {bubbles:true}));")
        #expect(sink.body == nil)
        let token = try await select(in: view, sink: sink)
        _ = try await view.evaluateJavaScript("history.pushState({},'', '/changed');")
        #expect(try await fill(token, in: view) == 0)
    }

    @Test(.boundedWebViews) func disabledManagerCannotFillCredentials() async throws {
        let (view, sink) = try await load(#"<form><input id="username" autocomplete="username"><input id="password" type="password" value="dummy-secret"></form>"#)
        let token = try await select(in: view, sink: sink)
        _ = try await view.callAsyncJavaScript("globalThis.__linenPasswords.setEnabled(false);", arguments: [:], in: nil, contentWorld: PasswordAutofill.world)
        #expect(try await fill(token, in: view) == 0)

    }

    @Test(.boundedWebViews) func refusesFormsThatSendPasswordsToAnotherOrigin() async throws {
        let (view, sink) = try await load(#"""
        <form action="https://other.example/post"><input id="username" autocomplete="username"><input id="password" type="password"></form>
        """#)
        _ = try await view.callAsyncJavaScript("password.focus();", arguments: [:], in: nil, contentWorld: PasswordAutofill.world)
        #expect(try await fill(UUID().uuidString, in: view) == 0)
        #expect(sink.body?["token"] as? String == nil)
    }

    @Test(.boundedWebViews) func componentInputsUseTheirOuterFormAndHostMetadata() async throws {
        let (view, sink) = try await load(#"""
        <form id="login" autocomplete="off" onsubmit="window.submitted=true; return false">
          <login-input id="account" name="username" autocomplete="username">
            <template shadowrootmode="open"><input type="text"></template>
          </login-input>
          <login-input id="secret" name="password" autocomplete="current-password">
            <template shadowrootmode="open"><input type="password"></template>
          </login-input>
        </form>
        <form><input id="other" type="password"></form>
        """#)
        _ = try await view.callAsyncJavaScript(
            "document.getElementById('secret').shadowRoot.querySelector('input').focus();",
            arguments: [:], in: nil, contentWorld: PasswordAutofill.world
        )
        #expect(await waitUntil { sink.body?["token"] is String })
        let token = try #require(sink.body?["token"] as? String)
        #expect(try await fill(token, in: view) == 2)
        #expect(try await view.evaluateJavaScript("account.shadowRoot.querySelector('input').value") as? String == "ada@example.test")
        #expect(try await view.evaluateJavaScript("secret.shadowRoot.querySelector('input').value") as? String == "dummy-secret")
        #expect(try await view.evaluateJavaScript("other.value") as? String == "")
        #expect(try await view.evaluateJavaScript("!!window.submitted") as? Bool == false)
    }

    @Test(.boundedWebViews) func hiddenComponentHostNeverQualifiesForPasswordFilling() async throws {
        let (view, sink) = try await load(#"""
        <form><input id="password" type="password" autocomplete="current-password">
          <login-input id="hidden-account" autocomplete="username" style="visibility:hidden">
            <template shadowrootmode="open"><input type="text" style="visibility:visible"></template>
          </login-input>
        </form>
        """#)
        let token = try await select(in: view, sink: sink)
        #expect(try await fill(token, in: view) == 1)
        #expect(try await view.evaluateJavaScript("document.getElementById('hidden-account').shadowRoot.querySelector('input').value") as? String == "")
    }

    @Test(.boundedWebViews) func movingFocusInvalidatesTheSuggestedLogin() async throws {
        let (view, sink) = try await load(#"<form><input id="password" type="password"><input id="other" autocomplete="one-time-code"></form>"#)
        let token = try await select(in: view, sink: sink)
        _ = try await view.evaluateJavaScript("other.focus();")
        #expect(try await fill(token, in: view) == 0)
        #expect(try await view.evaluateJavaScript("password.value + other.value") as? String == "")
    }

    @Test(.boundedWebViews) func usernameFirstStepFillsOnlyTheAccountWithoutSubmitting() async throws {
        let (view, sink) = try await load(#"<form onsubmit="window.submitted=true; return false"><input id="password" autocomplete="username"><button>Continue</button></form>"#)
        let token = try await select(in: view, sink: sink)
        #expect(try await fill(token, in: view) == 1)
        #expect(try await view.evaluateJavaScript("password.value") as? String == "ada@example.test")
        #expect(try await view.evaluateJavaScript("!!window.submitted") as? Bool == false)
    }

    @Test(.boundedWebViews) func recognizesAFormlessAccountStepWithWebAuthnMetadata() async throws {
        let (view, sink) = try await load(#"""
        <div id="sign_in_form"><div><div><div><div><input id="password" autocomplete="username webauthn"></div></div></div></div>
          <button type="submit">Continue</button><button>Sign in with Passkey</button>
        </div>
        <div><input id="unrelated" autocomplete="username"><button>Continue</button></div>
        """#)
        let token = try await select(in: view, sink: sink)
        #expect(try await fill(token, in: view) == 1)
        #expect(try await view.evaluateJavaScript("password.value") as? String == "ada@example.test")
        #expect(try await view.evaluateJavaScript("unrelated.value") as? String == "")
    }

    @Test(.boundedWebViews) func recognizesAFormlessPasswordStepWithoutMergingAnotherLogin() async throws {
        let (view, sink) = try await load(#"""
        <div><input id="password" type="password" autocomplete="current-password"><button>Sign In</button></div>
        <div><input id="unrelated" type="password"><button>Sign In</button></div>
        """#)
        let token = try await select(in: view, sink: sink)
        #expect(try await fill(token, in: view) == 1)
        #expect(try await view.evaluateJavaScript("password.value") as? String == "dummy-secret")
        #expect(try await view.evaluateJavaScript("unrelated.value") as? String == "")
    }

    @Test(.boundedWebViews) func standalonePasswordDoesNotRequireAFormOrSubmitButton() async throws {
        let (view, sink) = try await load(#"<input id="password" type="password">"#)
        let token = try await select(in: view, sink: sink)
        #expect(try await fill(token, in: view) == 1)
        #expect(try await view.evaluateJavaScript("password.value") as? String == "dummy-secret")
    }

    @Test(.boundedWebViews) func unlabelledComponentFieldsShareOwnershipWithoutEnglishActions() async throws {
        let (view, sink) = try await load(#"""
        <section>
          <div><input id="account"></div>
          <div><input id="password" type="password"><button type="button" aria-pressed="false">👁</button></div>
          <button type="button">Continuer</button>
        </section>
        <section><input id="unrelated" type="password"><button>Weiter</button></section>
        """#)
        let token = try await select(in: view, sink: sink)
        #expect(try await fill(token, in: view) == 2)
        #expect(try await view.evaluateJavaScript("account.value") as? String == "ada@example.test")
        #expect(try await view.evaluateJavaScript("unrelated.value") as? String == "")
    }

    @Test(.boundedWebViews) func disabledPasswordStillBlocksSubmissionCompletion() async throws {
        let (view, _) = try await load(#"<form><input id="password" type="password" disabled></form>"#)
        let result = try await view.callAsyncJavaScript(
            "return globalThis.__linenAutofillForms.summary().passwords;", arguments: [:],
            in: nil, contentWorld: PasswordAutofill.world
        )
        #expect(result as? Int == 1)
    }
}
