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
        windowAdapter.map { [$0] } ?? []
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        focusedWindowFor extensionContext: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        windowAdapter
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewTabUsing configuration: WKWebExtension.TabConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void
    ) {
        guard let tab = onOpenTab?(configuration.url) else {
            completionHandler(nil, nil)
            return
        }
        completionHandler(adapter(for: tab), nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void
    ) {
        _ = onOpenTab?(configuration.tabURLs.first)
        completionHandler(windowAdapter, nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openOptionsPageFor extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        _ = onOpenTab?(extensionContext.optionsPageURL)
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
        Task { @MainActor in
            let granted = await ExtensionConsent.confirmRuntimeGrant(
                name: name,
                permissions: permissions,
                matchPatterns: [],
                in: NSApp.keyWindow ?? NSApp.mainWindow
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
        Task { @MainActor in
            let granted = await ExtensionConsent.confirmRuntimeURLAccess(
                name: name,
                urls: urls,
                in: NSApp.keyWindow ?? NSApp.mainWindow
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
        Task { @MainActor in
            let granted = await ExtensionConsent.confirmRuntimeGrant(
                name: name,
                permissions: [],
                matchPatterns: matchPatterns,
                in: NSApp.keyWindow ?? NSApp.mainWindow
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
        if !present(action, for: context.uniqueIdentifier) {
            Pipeline.log.notice("ext: no toolbar anchor for \(context.uniqueIdentifier, privacy: .public), popup skipped")
        }
        completionHandler(nil)
    }
}
