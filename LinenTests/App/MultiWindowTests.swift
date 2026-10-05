// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct MultiWindowTests {
    private func window(in app: BrowserApplication, context: BrowserProfileContext) -> AppCoordinator {
        let browser = BrowserModel(context: context, windowID: UUID())
        let coordinator = AppCoordinator(browser: browser)
        app.register(coordinator)
        return coordinator
    }

    @Test func closingANativeWindowKeepsItsSessionAndTheOtherWindowOpen() throws {
        let app = BrowserApplication()
        let context = BrowserProfileContext.shared(for: .original())
        let first = window(in: app, context: context)
        let second = window(in: app, context: context)
        let firstTab = first.browser.newTab()
        let secondTab = second.browser.newTab()
        defer {
            first.closeWindow()
            second.closeWindow()
        }
        weak var closedHost: BrowserHost?
        // Drain AppKit's temporary references before checking host deallocation.
        let secondNativeWindow = try autoreleasepool {
            first.showBrowser(activate: false)
            second.showBrowser(activate: false)
            let firstNativeWindow = try #require(first.nativeWindow)
            let secondNativeWindow = try #require(second.nativeWindow)
            closedHost = firstNativeWindow.delegate as? BrowserHost
            #expect(firstNativeWindow !== secondNativeWindow)
            #expect(closedHost != nil)
            first.closeWindow()
            return secondNativeWindow
        }

        let saved = try #require(BrowserModel.savedWindows(in: context.database, includeClosed: true)
            .first { $0.id == first.windowID })
        #expect(saved.closedAt != nil)
        #expect(first.nativeWindow == nil)
        #expect(closedHost == nil)
        #expect(app.windows.count == 1)
        #expect(app.windows.first === second)
        #expect(second.nativeWindow === secondNativeWindow)
        #expect(secondNativeWindow.isVisible)
        #expect(second.browser.activeTab === secondTab)
        #expect(!secondTab.isClosed)

        first.closeWindow()
        #expect(app.windows.count == 1)
        #expect(BrowserModel.savedWindows(in: context.database, includeClosed: true)
            .first { $0.id == first.windowID }?.closedAt == saved.closedAt)
        let restored = BrowserModel(context: context, windowID: first.windowID)
        restored.restoreSession()
        defer {
            restored.markSessionClosed()
            restored.closeAllTabs(saving: false)
        }
        #expect(restored.tabs.map(\.id) == [firstTab.id])
    }

    @Test func windowsShareProfileDataButKeepTheirSelectionIndependent() {
        let app = BrowserApplication()
        let context = BrowserProfileContext.shared(for: .original())
        let first = window(in: app, context: context)
        let second = window(in: app, context: context)
        let firstTab = first.browser.newTab()
        let secondTab = second.browser.newTab()
        defer {
            first.closeWindow()
            second.closeWindow()
        }

        #expect(first.windowID != second.windowID)
        #expect(first.browser.context === second.browser.context)
        #expect(first.browser.history === second.browser.history)
        #expect(first.browser.downloads === second.browser.downloads)
        #expect(first.conversationLog === second.conversationLog)
        #expect(first.browser.activeTab === firstTab)
        #expect(second.browser.activeTab === secondTab)
        app.focus(first)
        #expect(app.activeCoordinator === first)
        app.focus(second)
        #expect(app.activeCoordinator === second)
    }

    @Test func closingOnePrivateWindowLeavesOtherWindowsAndTheirDataAvailable() {
        let app = BrowserApplication()
        let regular = window(in: app, context: .shared(for: .original()))
        let first = window(in: app, context: .shared(for: .privateBrowsing()))
        let second = window(in: app, context: .shared(for: .privateBrowsing()))
        let regularTab = regular.browser.newTab()
        let privateTab = first.browser.newTab()
        let otherPrivateTab = second.browser.newTab()
        let firstTrace = first.conversationLog.beginTask("first private window", tabID: privateTab.id)
        first.conversationLog.completeTask(firstTrace, response: "done")
        let secondTrace = second.conversationLog.beginTask("second private window", tabID: otherPrivateTab.id)
        second.conversationLog.completeTask(secondTrace, response: "done")
        defer {
            regular.closeWindow()
            second.closeWindow()
        }

        #expect(first.browser.context !== second.browser.context)
        #expect(first.browser.context.dataStore !== second.browser.context.dataStore)
        #expect(!first.browser.context.dataStore.isPersistent)
        #expect(!second.browser.adoptTab(privateTab, from: first.browser))
        app.focus(second)
        #expect(app.externalLinkTarget === regular)
        first.closeWindow()

        #expect(app.windows.count == 2)
        #expect(privateTab.isClosed)
        #expect(first.conversationLog.traces.isEmpty)
        #expect(regular.browser.activeTab === regularTab)
        #expect(second.browser.activeTab === otherPrivateTab)
        #expect(!regularTab.isClosed)
        #expect(!otherPrivateTab.isClosed)
        #expect(second.conversationLog.traces(forTab: otherPrivateTab.id).count == 1)
    }

    @Test func movingTabsIgnoresClosedWindowEndpoints() {
        let app = BrowserApplication()
        let context = BrowserProfileContext.shared(for: .original())
        let closedWindow = window(in: app, context: context)
        let openWindow = window(in: app, context: context)
        let closedTab = closedWindow.browser.newTab()
        let openTab = openWindow.browser.newTab()
        defer { openWindow.closeWindow() }
        closedWindow.closeWindow()

        #expect(!closedWindow.moveTab(closedTab, to: openWindow))
        #expect(!openWindow.moveTab(openTab, to: closedWindow))
        #expect(openWindow.browser.activeTab === openTab)
        #expect(!openTab.isClosed)
        #expect(closedWindow.browser.tabs.isEmpty)
        #expect(closedWindow.nativeWindow == nil)
        #expect(app.windows.count == 1)
    }

    @Test func externalLinksUseTheLastFocusedRegularWindowWhilePrivateIsActive() {
        let app = BrowserApplication()
        let context = BrowserProfileContext.shared(for: .original())
        let first = window(in: app, context: context)
        let second = window(in: app, context: context)
        let privateWindow = window(in: app, context: .shared(for: .privateBrowsing()))
        defer {
            first.closeWindow()
            second.closeWindow()
            privateWindow.closeWindow()
        }

        app.focus(second)
        app.focus(first)
        app.focus(privateWindow)
        #expect(app.activeCoordinator === privateWindow)
        #expect(app.externalLinkTarget === first)
        first.closeWindow()
        #expect(app.externalLinkTarget === second)
    }

    @Test func clearOnQuitRemainsEligibleAfterTheLastRegularWindowCloses() {
        let app = BrowserApplication()
        let context = BrowserProfileContext.shared(for: .original())
        let originalPreference = context.settings.clearsDataOnQuit
        defer { context.settings.clearsDataOnQuit = originalPreference }
        context.settings.clearsDataOnQuit = true
        let regular = window(in: app, context: context)
        #expect(app.hasDataToClearOnQuit)

        regular.closeWindow()

        #expect(app.windows.isEmpty)
        #expect(app.hasDataToClearOnQuit)
    }

    @Test func privateContextReleasedAfterClosing() async {
        let app = BrowserApplication()
        weak var releasedContext: BrowserProfileContext?
        weak var releasedWindow: AppCoordinator?
        do {
            let context = BrowserProfileContext.shared(for: .privateBrowsing())
            releasedContext = context
            let privateWindow = window(in: app, context: context)
            releasedWindow = privateWindow
            privateWindow.followSettings()
            _ = privateWindow.browser.newTab()
            privateWindow.closeWindow()
        }

        #expect(app.windows.isEmpty)
        #expect(await waitUntil { releasedWindow == nil && releasedContext == nil })
    }

    @Test func closingAndReopeningARegularWindowKeepsItsConversation() {
        let app = BrowserApplication()
        let context = BrowserProfileContext.shared(for: .original())
        let original = window(in: app, context: context)
        let tab = original.browser.newTab()
        let traceID = original.conversationLog.beginTask("saved work", tabID: tab.id)
        original.conversationLog.completeTask(traceID, response: "saved answer")
        original.closeWindow()

        #expect(app.windows.isEmpty)
        #expect(BrowserModel.savedWindows(in: context.database, includeClosed: true)
            .first { $0.id == original.windowID }?.closedAt != nil)
        #expect(context.conversationLog.traces(forTab: tab.id).first?.response == "saved answer")
        let browser = BrowserModel(context: context, windowID: original.windowID)
        browser.restoreSession()
        let restored = AppCoordinator(browser: browser)
        app.register(restored)
        defer { restored.closeWindow() }

        #expect(browser.activeTab?.id == tab.id)
        #expect(restored.conversationLog.traces(forTab: tab.id).first?.response == "saved answer")
        #expect(BrowserModel.savedWindows(in: context.database).contains { $0.id == original.windowID })
    }
}
