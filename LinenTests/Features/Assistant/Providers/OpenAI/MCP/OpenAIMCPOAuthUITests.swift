// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import Testing

@testable import Linen

@MainActor
struct OpenAIMCPOAuthUITests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LINEN_OAUTH_UI_TEST"] == "1"))
    func authenticationSessionCompletionAndSettingsRemainUsable() async throws {
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 650, height: 720),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Linen OAuth verification"
        window.contentView = NSHostingView(rootView: Text("Focus this window to verify OAuth sign-in.").padding().frame(width: 650, height: 720))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try #require(await waitUntil(timeout: .seconds(60)) { NSApp.isActive && window.isKeyWindow })
        let callback = URL(string: "com.kavoye.linen.oauth://callback?state=fixture&code=fixture")!
        let site = try await HTTPFixtureServer.start(routes: ["/authorize": .redirect(to: callback)])
        let session = OpenAIMCPOAuthSession(window: window)
        let authorization = try site.url("/authorize")
        let result = try await session.authenticate(authorization)
        let isDryRun = result == authorization
        try #require(isDryRun || result == callback)
        print("LINEN_OAUTH_UI_AUTHENTICATION_MODE=\(isDryRun ? "dry_run" : "fixture_redirect")")
        window.title = isDryRun ? "Linen OAuth verification: test callback" : "Linen OAuth verification: fixture redirect"
        let connection = OpenAIMCPServer(label: "Example_MCP", destination: "https://mcp.example.test/mcp", requiresAuthorization: true,
                                         oauth: .init(issuer: "https://identity.example.test", clientID: "", scope: "files:read"))
        let transport = OAuthSetupFixture([.init(status: 401, data: Data()), try .setupJSON(OpenAIMCPOAuthSetupTests.resource),
                                           try .setupJSON(OpenAIMCPOAuthSetupTests.metadata), try .setupJSON(OpenAIMCPOAuthSetupTests.registration, status: 201),
        ])
        window.contentView = NSHostingView(rootView: ScrollView {
            OpenAIMCPSettingsView(providerID: "oauth-ui-fixture", servers: .constant([connection]), oauthSetup: .init(transport: transport)).padding()
        }.frame(width: 650, height: 720))
        #expect(await waitUntil(timeout: .seconds(60)) { !window.isVisible })
        #expect(await transport.requests.count == 4)
        #expect(await transport.requests.last?.url?.path == "/register")
    }
}
