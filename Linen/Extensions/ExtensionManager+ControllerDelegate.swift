// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import os
import WebKit

extension ExtensionManager {
    func webExtensionController(
        _ controller: WKWebExtensionController,
        openWindowsFor extensionContext: WKWebExtensionContext
    ) -> [any WKWebExtensionWindow] {
        windowAdapters
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        focusedWindowFor extensionContext: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        focusedWindowAdapter
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewTabUsing configuration: WKWebExtension.TabConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void
    ) {
        let target: ExtensionWindowAdapter?
        if let requested = configuration.window {
            guard let window = requested as? ExtensionWindowAdapter,
                  windowAdapters.contains(where: { $0 === window }) else {
                completionHandler(nil, ExtensionWindowError.unavailable)
                return
            }
            target = window
        } else {
            target = preferredWindowAdapter
        }
        guard let browser = target?.browser else {
            completionHandler(nil, ExtensionWindowError.unavailable)
            return
        }
        let parent = (configuration.parentTab as? ExtensionTabAdapter)?.tab
        let tab = browser.newTab(url: configuration.url, activate: configuration.shouldBeActive, after: parent)
        if configuration.shouldBePinned {
            browser.pin(tab)
        }
        let others = browser.tabs.filter { $0 !== tab }
        if configuration.index >= 0, configuration.index < others.count {
            browser.move([.tab(tab.id)], into: nil, before: .tab(others[configuration.index].id))
        } else if configuration.index != NSNotFound {
            browser.move([.tab(tab.id)], into: nil, before: nil)
        }
        completionHandler(adapter(for: tab), nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void
    ) {
        // Every private window is a separate session, so its live tabs cannot enter another window.
        guard configuration.tabs.isEmpty || (!configuration.shouldBePrivate && profile?.isPrivate != true) else {
            completionHandler(nil, ExtensionWindowError.foreignTab)
            return
        }
        // Validate before creating a window so a bad request cannot partially move a workspace.
        guard configuration.tabs.allSatisfy({ candidate in
            guard let tab = candidate as? ExtensionTabAdapter, let browser = tab.browser else { return false }
            return adapter(for: browser) != nil
        }) else {
            completionHandler(nil, ExtensionWindowError.foreignTab)
            return
        }
        guard let window = onOpenWindow?(configuration) else {
            completionHandler(nil, ExtensionWindowError.creationFailed)
            return
        }
        window.apply(configuration: configuration)
        completionHandler(window, nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openOptionsPageFor extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        _ = openTab(extensionContext.optionsPageURL)
        completionHandler(nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissions permissions: Set<WKWebExtension.Permission>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void
    ) {
        let name = extensionContext.webExtension.displayName ?? extensionContext.uniqueIdentifier
        let window = (tab as? ExtensionTabAdapter)?.browser.flatMap { adapter(for: $0)?.nativeWindow }
            ?? preferredWindowAdapter?.nativeWindow
        Task { @MainActor in
            let granted = await ExtensionConsent.confirmRuntimeGrant(
                name: name,
                permissions: permissions,
                matchPatterns: [],
                in: window
            )
            completionHandler(granted ? permissions : [], nil)
        }
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionToAccess urls: Set<URL>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<URL>, Date?) -> Void
    ) {
        let name = extensionContext.webExtension.displayName ?? extensionContext.uniqueIdentifier
        let window = (tab as? ExtensionTabAdapter)?.browser.flatMap { adapter(for: $0)?.nativeWindow }
            ?? preferredWindowAdapter?.nativeWindow
        Task { @MainActor in
            let granted = await ExtensionConsent.confirmRuntimeURLAccess(
                name: name,
                urls: urls,
                in: window
            )
            completionHandler(granted ? urls : [], nil)
        }
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void
    ) {
        let name = extensionContext.webExtension.displayName ?? extensionContext.uniqueIdentifier
        let window = (tab as? ExtensionTabAdapter)?.browser.flatMap { adapter(for: $0)?.nativeWindow }
            ?? preferredWindowAdapter?.nativeWindow
        Task { @MainActor in
            let granted = await ExtensionConsent.confirmRuntimeGrant(
                name: name,
                permissions: [],
                matchPatterns: matchPatterns,
                in: window
            )
            completionHandler(granted ? matchPatterns : [], nil)
        }
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        didUpdate action: WKWebExtension.Action,
        forExtensionContext context: WKWebExtensionContext
    ) {
        noteActionUpdate()
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        presentActionPopup action: WKWebExtension.Action,
        for context: WKWebExtensionContext,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        if !present(action, for: context.uniqueIdentifier, in: (action.associatedTab as? ExtensionTabAdapter)?.browser) {
            Pipeline.log.notice("Extension popup skipped: no toolbar anchor")
        }
        completionHandler(nil)
    }
}
