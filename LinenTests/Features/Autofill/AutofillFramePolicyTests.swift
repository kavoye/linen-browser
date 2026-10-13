// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct AutofillFramePolicyTests {
    private final class Frames: NSObject, WKScriptMessageHandler {
        var values: [String: WKFrameInfo] = [:]

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], body["action"] as? String == "ready",
                  let documentID = body["documentID"] as? String else { return }
            values[documentID] = message.frameInfo
        }
    }

    @Test func passwordPolicyInSandboxedFrames() async throws {
        let configuration = interactiveWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let frames = Frames()
        configuration.userContentController.add(frames, contentWorld: PasswordAutofill.world, name: "linenPasswords")
        configuration.userContentController.addUserScript(WKUserScript(
            source: PasswordAutofillScript.source, injectionTime: .atDocumentStart,
            forMainFrameOnly: false, in: PasswordAutofill.world
        ))
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        view.loadHTMLString("""
        <!doctype html><input type="password">
        <iframe srcdoc="<input type='password'>"></iframe>
        <iframe sandbox="allow-scripts" srcdoc="<input type='password'>"></iframe>
        <iframe sandbox="allow-same-origin" srcdoc="<input type='password'>"></iframe>
        <iframe sandbox srcdoc="<input type='password'>"></iframe>
        """, baseURL: URL(string: "https://login.example/"))
        #expect(await PageSettle.untilIdle(view, timeout: .seconds(20)))
        #expect(await waitUntil { frames.values.count == 5 })
        for frame in frames.values.values {
            do {
                _ = try await view.callAsyncJavaScript(
                    "globalThis.__linenPasswords?.setEnabled(enabled);", arguments: ["enabled": true],
                    in: frame, contentWorld: PasswordAutofill.world
                )
            } catch {
                Issue.record("Policy failed: main=\(frame.isMainFrame), origin=\(frame.securityOrigin.protocol), error=\(error)")
            }
        }
    }
}
