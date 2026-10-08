// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct ExtensionWindowTests {
    private func extensionContext() async throws -> WKWebExtensionContext {
        let directory = TestFiles.directory
            .appendingPathComponent("linen-extension-windows-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(#"{"manifest_version":3,"name":"Windows","version":"1.0"}"#.utf8)
            .write(to: directory.appendingPathComponent("manifest.json"))
        return WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: directory))
    }

    @Test func registeringAnotherWindowKeepsTheProfileControllerAndCallbacks() {
        let manager = ExtensionManager(profile: .original())
        let controller = manager.controller
        let first = BrowserModel(database: .temporary())
        let second = BrowserModel(database: .temporary())
        let adapter = manager.register(browser: first)
        var activations = 0
        let original = first.onActiveTabChanged
        first.onActiveTabChanged = { new, previous in
            original?(new, previous)
            activations += 1
        }

        manager.register(browser: second)
        #expect(manager.register(browser: first) === adapter)
        _ = first.newTab()

        #expect(manager.controller === controller)
        #expect(manager.windowAdapters.count == 2)
        #expect(activations == 1)
        manager.unregister(browser: second)
        #expect(manager.windowAdapters.count == 1)
        #expect(manager.adapter(for: first) === adapter)
        manager.unregister(browser: first)
    }

    @Test func theExtensionSeesEveryWindowAndOnlyThatWindowsTabs() async throws {
        let context = try await extensionContext()
        let manager = ExtensionManager()
        let first = BrowserModel(database: .temporary())
        let second = BrowserModel(database: .temporary())
        let firstWindow = manager.register(browser: first)
        let secondWindow = manager.register(browser: second)
        let firstTab = first.newTab()
        let secondTab = second.newTab()
        defer {
            manager.unregister(browser: first)
            manager.unregister(browser: second)
        }

        let windows = manager.webExtensionController(manager.controller, openWindowsFor: context)
        #expect(windows.count == 2)
        #expect((firstWindow.tabs(for: context).first as? ExtensionTabAdapter)?.tab === firstTab)
        #expect((secondWindow.tabs(for: context).first as? ExtensionTabAdapter)?.tab === secondTab)
        #expect((manager.adapter(for: firstTab).window(for: context) as? ExtensionWindowAdapter) === firstWindow)
        #expect((manager.adapter(for: secondTab).window(for: context) as? ExtensionWindowAdapter) === secondWindow)
    }

    @Test func aTransferredTabKeepsItsExtensionIdentityAndChangesWindow() async throws {
        let context = try await extensionContext()
        let manager = ExtensionManager()
        let database = AppDatabase.temporary()
        let first = BrowserModel(windowID: UUID(), database: database)
        let second = BrowserModel(windowID: UUID(), database: database)
        manager.register(browser: first)
        let destination = manager.register(browser: second)
        let tab = first.newTab()
        let adapter = manager.adapter(for: tab)
        defer {
            manager.unregister(browser: first)
            manager.unregister(browser: second)
        }

        #expect(second.adoptTab(tab, from: first))
        #expect(manager.adapter(for: tab) === adapter)
        #expect(adapter.browser === second)
        #expect((adapter.window(for: context) as? ExtensionWindowAdapter) === destination)
        #expect(adapter.indexInWindow(for: context) == 0)
        #expect(first.tabs.isEmpty)
        #expect(!tab.isClosed)
    }

    @Test func eachAdapterUsesItsOwnNativeFrameAndPrivateStatus() async throws {
        let context = try await extensionContext()
        let normal = ExtensionManager(profile: .original())
        let privateManager = ExtensionManager(profile: .privateBrowsing())
        let first = BrowserModel(database: .temporary())
        let second = BrowserModel(database: .temporary())
        let firstNative = NSWindow(contentRect: NSRect(x: 10, y: 20, width: 700, height: 500), styleMask: [], backing: .buffered, defer: true)
        let secondNative = NSWindow(contentRect: NSRect(x: 80, y: 90, width: 600, height: 400), styleMask: [], backing: .buffered, defer: true)
        firstNative.isReleasedWhenClosed = false
        secondNative.isReleasedWhenClosed = false
        let firstWindow = normal.register(browser: first, window: firstNative)
        let secondWindow = privateManager.register(browser: second, window: secondNative)
        defer {
            normal.unregister(browser: first)
            privateManager.unregister(browser: second)
            firstNative.close()
            secondNative.close()
        }

        #expect(firstWindow.frame(for: context) == firstNative.frame)
        #expect(secondWindow.frame(for: context) == secondNative.frame)
        #expect(!firstWindow.isPrivate(for: context))
        #expect(secondWindow.isPrivate(for: context))
        let moved = CGRect(x: 100, y: 200, width: 800, height: 600)
        secondWindow.setFrame(moved, for: context) { error in #expect(error == nil) }
        #expect(secondNative.frame == moved)
        #expect(firstNative.frame != moved)
    }

    @Test func retiredAdaptersCannotReadOrChangeTheBrowsersNextProfile() async throws {
        let context = try await extensionContext()
        let personal = ExtensionManager()
        let work = ExtensionManager()
        let browser = BrowserModel(database: .temporary())
        let oldWindow = personal.register(browser: browser)
        let oldTab = browser.newTab()
        let oldAdapter = personal.adapter(for: oldTab)

        personal.unregister(browser: browser)
        browser.closeAllTabs(saving: false)
        let newWindow = work.register(browser: browser)
        let newTab = browser.newTab()
        defer {
            work.unregister(browser: browser)
            browser.closeAllTabs(saving: false)
        }

        #expect(oldWindow.browser == nil)
        #expect(oldWindow.tabs(for: context).isEmpty)
        #expect(oldWindow.activeTab(for: context) == nil)
        #expect(oldAdapter.tab == nil)
        #expect(oldAdapter.webView(for: context) == nil)
        #expect(oldAdapter.window(for: context) == nil)
        #expect(oldAdapter.indexInWindow(for: context) == NSNotFound)
        #expect(!oldAdapter.isSelected(for: context))
        oldAdapter.activate(for: context) { #expect($0 as? ExtensionWindowError == .unavailable) }
        oldAdapter.close(for: context) { #expect($0 as? ExtensionWindowError == .unavailable) }
        #expect(browser.activeTab === newTab)
        #expect(!newTab.isClosed)
        #expect((newWindow.activeTab(for: context) as? ExtensionTabAdapter)?.tab === newTab)
    }

    @Test func capturedCallbacksStayRetiredWhenTheSameBrowserRegistersAgain() throws {
        let manager = ExtensionManager()
        let browser = BrowserModel(database: .temporary())
        let oldWindow = manager.register(browser: browser)
        let didOpen = try #require(browser.onTabOpened)
        let didClose = try #require(browser.onTabClosed)
        let didActivate = try #require(browser.onActiveTabChanged)
        manager.unregister(browser: browser)
        let newWindow = manager.register(browser: browser)
        let newTab = browser.newTab()
        let newAdapter = manager.adapter(for: newTab)
        let foreign = BrowserModel(database: .temporary())
        let foreignTab = foreign.newTab()
        defer {
            manager.unregister(browser: browser)
            browser.closeAllTabs(saving: false)
            foreign.closeAllTabs(saving: false)
        }

        didOpen(foreignTab)
        didActivate(foreignTab, nil)
        didClose(newTab)

        #expect(!manager.owns(oldWindow))
        #expect(manager.owns(newWindow))
        #expect(manager.tabAdapters[newTab.id] === newAdapter)
        #expect(manager.tabAdapters[foreignTab.id] == nil)
        #expect(newAdapter.tab === newTab)
    }

    @Test func unregisteringAfterTabsAreClearedStillInvalidatesTheirAdapters() {
        let manager = ExtensionManager()
        let browser = BrowserModel(database: .temporary())
        manager.register(browser: browser)
        let tab = browser.newTab()
        let adapter = manager.adapter(for: tab)

        browser.closeAllTabs(saving: false)
        manager.unregister(browser: browser)

        #expect(manager.tabAdapters.isEmpty)
        #expect(adapter.tab == nil)
        #expect(adapter.browser == nil)
    }

    @Test func staleToolbarCallsCannotUseAnotherProfilesTabsOrFallbackWindow() async throws {
        let directory = TestFiles.directory
            .appendingPathComponent("linen-extension-toolbar-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = ExtensionLibrary(baseDirectory: directory)
        let id = "window-registration-test"
        let package = library.packageURL(for: id)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data(#"{"manifest_version":3,"name":"Windows","version":"1.0","action":{"default_title":"Windows"}}"#.utf8)
            .write(to: package.appendingPathComponent("manifest.json"))
        library.recordInstall(id: id)
        let personal = ExtensionManager(library: library)
        let work = ExtensionManager()
        let browser = BrowserModel(database: .temporary())
        let sibling = BrowserModel(database: .temporary())
        personal.register(browser: browser)
        personal.register(browser: sibling)
        _ = browser.newTab()
        _ = sibling.newTab()
        defer {
            personal.unregister(browser: browser)
            personal.unregister(browser: sibling)
            work.unregister(browser: browser)
            browser.closeAllTabs(saving: false)
            sibling.closeAllTabs(saving: false)
            personal.beginAdopting(profile: nil)
        }
        await personal.start()
        _ = try #require(personal.contexts[id])
        _ = try #require(personal.action(for: id, in: browser))

        personal.unregister(browser: browser)
        browser.closeAllTabs(saving: false)
        work.register(browser: browser)
        let workTab = browser.newTab()
        let siblingCount = sibling.tabs.count

        #expect(personal.action(for: id, in: browser) == nil)
        #expect(personal.contextMenu(for: id, in: browser) == nil)
        personal.performAction(for: id, in: browser)
        #expect(personal.openTab(nil, in: browser) == nil)
        #expect(sibling.tabs.count == siblingCount)
        #expect(browser.tabs.map(\.id) == [workTab.id])
        #expect(personal.tabAdapters[workTab.id] == nil)
        #expect(personal.action(for: id, in: sibling) != nil)
    }
}
