// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import MCP
import Testing

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct MCPWindowScopeTests {
    private func window(in app: BrowserApplication, privately: Bool = false) -> AppCoordinator {
        let context = BrowserProfileContext.shared(for: privately ? .privateBrowsing() : .original())
        let coordinator = AppCoordinator(browser: BrowserModel(context: context, windowID: UUID()))
        app.register(coordinator)
        return coordinator
    }

    private func nativeWindow(for coordinator: AppCoordinator) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 20, y: 20, width: 700, height: 500),
            styleMask: [], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        coordinator.extensions.register(browser: coordinator.browser, window: window)
        return window
    }

    private func call(_ session: MCPBrowserSession, _ name: String, arguments: [String: Value] = [:]) async throws -> CallTool.Result {
        try await session.call(name: name, arguments: arguments)
    }

    @Test func focusChangesDoNotRetargetAnExistingConnection() async throws {
        let app = BrowserApplication()
        let first = window(in: app)
        let second = window(in: app)
        let privateWindow = window(in: app, privately: true)
        defer {
            first.closeWindow()
            second.closeWindow()
            privateWindow.closeWindow()
        }

        app.focus(first)
        let firstConnection = try #require(app.mcpServer.makeSessionForConnection())
        app.focus(second)
        let secondConnection = try #require(app.mcpServer.makeSessionForConnection())

        #expect(firstConnection.isBound(to: first.browser))
        #expect(!firstConnection.isBound(to: second.browser))
        #expect(secondConnection.isBound(to: second.browser))
        app.focus(privateWindow)
        #expect(app.mcpServer.makeSessionForConnection() == nil)
        #expect(try await call(firstConnection, "listTabs").isError == false)
        #expect(try await call(secondConnection, "listTabs").isError == false)
    }

    @Test func closingOneWindowMakesOnlyItsConnectionUnavailable() async throws {
        let app = BrowserApplication()
        let first = window(in: app)
        let second = window(in: app)
        defer { second.closeWindow() }
        app.focus(first)
        let firstConnection = try #require(app.mcpServer.makeSessionForConnection())
        app.focus(second)
        let secondConnection = try #require(app.mcpServer.makeSessionForConnection())

        first.closeWindow()

        #expect(try await call(firstConnection, "listTabs").isError == true)
        #expect(try await call(firstConnection, "requestAccess").isError == true)
        #expect(try await call(secondConnection, "listTabs").isError == false)
        #expect(app.mcpServer.makeSessionForConnection()?.isBound(to: second.browser) == true)
    }

    @Test func replacingTheBoundProfileContextDoesNotReauthorizeTheConnection() async throws {
        let app = BrowserApplication()
        let first = window(in: app)
        let second = window(in: app)
        let original = first.browser.context
        defer {
            first.browser.context = original
            first.closeWindow()
            second.closeWindow()
        }
        app.focus(first)
        let firstConnection = try #require(app.mcpServer.makeSessionForConnection())
        app.focus(second)
        let secondConnection = try #require(app.mcpServer.makeSessionForConnection())

        // A profile switch keeps the BrowserModel but adopts another profile's services.
        first.browser.context = .shared(for: .privateBrowsing())
        app.focus(first)

        #expect(app.mcpServer.makeSessionForConnection() == nil)
        #expect(try await call(firstConnection, "listTabs").isError == true)
        #expect(try await call(firstConnection, "requestAccess").isError == true)
        #expect(try await call(secondConnection, "listTabs").isError == false)
        #expect(firstConnection.isBound(to: first.browser))
    }

    @Test func consentAndNewPageConsentStayWithTheOriginalNativeWindow() async throws {
        let app = BrowserApplication()
        let first = window(in: app)
        let second = window(in: app)
        let firstNative = nativeWindow(for: first)
        let secondNative = nativeWindow(for: second)
        defer {
            first.closeWindow()
            second.closeWindow()
            firstNative.close()
            secondNative.close()
        }
        let tab = await parkTab(first.browser, at: try #require(URL(string: "https://first-window.invalid/")))
        app.focus(first)
        var shareWindow: NSWindow?
        var openWindow: NSWindow?
        var sharedPages: [MCPAccessConsent.Page] = []
        let connection = try #require(app.mcpServer.makeSessionForConnection(
            consent: { _, pages, window in
                shareWindow = window
                sharedPages = pages
                return .control
            },
            openConsent: { _, _, window in
                openWindow = window
                return false
            }
        ))
        app.focus(second)

        #expect(try await call(connection, "requestAccess").isError == false)
        #expect(shareWindow === firstNative)
        #expect(sharedPages.map(\.id) == [tab.id])
        #expect(try await call(connection, "newTab", arguments: ["url": "https://first-window.invalid/next"]).isError == true)
        #expect(openWindow === firstNative)
        #expect(first.browser.tabs.count == 1)
        #expect(second.browser.tabs.isEmpty)
    }

    @Test func missingWindowCannotSendConsentToAnotherWindowsSheet() async throws {
        let app = BrowserApplication()
        let first = window(in: app)
        let second = window(in: app)
        let secondNative = nativeWindow(for: second)
        defer {
            first.closeWindow()
            second.closeWindow()
            secondNative.close()
        }
        _ = await parkTab(first.browser, at: try #require(URL(string: "https://first-window.invalid/")))
        app.focus(first)
        var prompts = 0
        let connection = try #require(app.mcpServer.makeSessionForConnection(consent: { _, _, _ in
            prompts += 1
            return .control
        }))
        app.focus(second)

        #expect(try await call(connection, "requestAccess").isError == true)
        #expect(prompts == 0)
        #expect(connection.grants.isEmpty)
    }
}
