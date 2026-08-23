// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Observation
import os
import WebKit

enum StoreInstallState: Equatable {
    case idle
    case installing(id: String)
    case installed(id: String)
    case failed(id: String, message: String)
}

@MainActor
@Observable
final class ExtensionManager: NSObject, WKWebExtensionControllerDelegate {
    private(set) var controller: WKWebExtensionController

    private(set) var installed: [InstalledExtension] = []
    private(set) var contexts: [String: WKWebExtensionContext] = [:]
    private(set) var actionRevision = 0
    var installState: StoreInstallState = .idle

    var onOpenTab: ((URL?) -> BrowserTab?)?

    private var library: ExtensionLibrary
    private let browser: BrowserModel

    @ObservationIgnored private var tabAdapters: [UUID: ExtensionTabAdapter] = [:]
    @ObservationIgnored private var windowAdapter: ExtensionWindowAdapter?
    @ObservationIgnored private var iconCache: [String: NSImage] = [:]
    @ObservationIgnored private var anchors: [String: NSView] = [:]
    @ObservationIgnored private weak var overflowAnchor: NSView?

    @ObservationIgnored private var presentedPopup: NSPopover?
    @ObservationIgnored private var presentedPopupID: String?
    @ObservationIgnored private var popupCloseObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var lastDismissedPopupID: String?
    @ObservationIgnored private var lastPopupDismissal = Date.distantPast
    @ObservationIgnored private var reloadedForEmptyPopup: Set<String> = []

    init(browser: BrowserModel, library: ExtensionLibrary = ExtensionLibrary()) {
        self.browser = browser
        self.library = library
        controller = WKWebExtensionController(configuration: .default())
        super.init()
        controller.delegate = self

        let window = ExtensionWindowAdapter(browser: browser, manager: self)
        windowAdapter = window

        browser.extensionPageHost = { [weak self] url in
            guard let context = self?.controller.extensionContext(for: url),
                  let configuration = context.webViewConfiguration else { return nil }
            let webExtension = context.webExtension
            return ExtensionPageHost(
                configuration: configuration,
                baseURL: context.baseURL,
                name: webExtension.displayName ?? String(localized: "Extension"),
                icon: webExtension.icon(for: CGSize(width: 32, height: 32))
            )
        }
        browser.onTabOpened = { [weak self] tab in
            guard let self else { return }
            controller.didOpenTab(adapter(for: tab))
        }
        browser.onTabClosed = { [weak self] tab in
            guard let self, let adapter = tabAdapters.removeValue(forKey: tab.id) else { return }
            controller.didCloseTab(adapter, windowIsClosing: false)
        }
        browser.onActiveTabChanged = { [weak self] newTab, previousTab in
            guard let self, let newTab else { return }
            let previous = previousTab.flatMap { tabAdapters[$0.id] }
            controller.didActivateTab(adapter(for: newTab), previousActiveTab: previous)
        }
    }

    func adapter(for tab: BrowserTab) -> ExtensionTabAdapter {
        if let existing = tabAdapters[tab.id] {
            return existing
        }
        let adapter = ExtensionTabAdapter(
            tab: tab,
            browser: browser,
            windowAdapter: windowAdapter ?? ExtensionWindowAdapter(browser: browser, manager: self)
        )
        tabAdapters[tab.id] = adapter
        return adapter
    }

    // MARK: - Lifecycle

    func useLibrary(for profile: Profile) {
        library = ExtensionLibrary(baseDirectory: profile.extensionsDirectory)
    }

    func adopt(profile: Profile?) async {
        for (_, context) in contexts {
            try? controller.unload(context)
        }
        contexts = [:]
        installed = []
        iconCache = [:]
        anchors = [:]
        reloadedForEmptyPopup = []
        presentedPopup?.performClose(nil)
        presentedPopup = nil
        presentedPopupID = nil

        controller = WKWebExtensionController(configuration: .default())
        controller.delegate = self
        guard let profile else { return }
        library = ExtensionLibrary(baseDirectory: profile.extensionsDirectory)
        await start()
    }

    func start() async {
        library.load()
        installed = library.records

        if let windowAdapter {
            controller.didOpenWindow(windowAdapter)
            controller.didFocusWindow(windowAdapter)
        }

        for record in installed where record.enabled {
            await load(record)
        }
    }

    private func load(_ record: InstalledExtension) async {
        guard contexts[record.id] == nil else { return }
        let state = Pipeline.signposter.beginInterval("ext.load")
        let started = ContinuousClock.now
        do {
            let package = library.packageURL(for: record.id)
            let webExtension = try await WKWebExtension(resourceBaseURL: package)
            if let icon = webExtension.icon(for: CGSize(width: 32, height: 32)) {
                iconCache[record.id] = icon
            }
            let context = WKWebExtensionContext(for: webExtension)
            // Set the identifier before the load. WebKit keys the extension's
            // persistent storage on it.
            context.uniqueIdentifier = record.id
            if let base = URL(string: "webkit-extension://\(record.id)/") {
                context.baseURL = base
            }
            #if DEBUG
            context.isInspectable = true
            #endif

            for permission in webExtension.requestedPermissions {
                context.setPermissionStatus(.grantedExplicitly, for: permission)
            }
            for pattern in webExtension.allRequestedMatchPatterns {
                context.setPermissionStatus(.grantedExplicitly, for: pattern)
            }

            try controller.load(context)
            contexts[record.id] = context
            library.updateMetadata(
                id: record.id,
                name: webExtension.displayName,
                version: webExtension.version
            )
            installed = library.records

            let name = webExtension.displayName ?? record.displayName
            let ms = (ContinuousClock.now - started).milliseconds
            Pipeline.log.notice("ext: loaded \(name, privacy: .public) in \(ms) ms")

            if webExtension.hasBackgroundContent {
                do {
                    try await context.loadBackgroundContent()
                    Pipeline.log.notice("""
                        ext: \(name, privacy: .public) background ready \
                        (blocking rules: \(context.hasContentModificationRules, privacy: .public))
                        """)
                } catch {
                    Pipeline.log.error("""
                        ext: \(name, privacy: .public) background failed: \
                        \(error, privacy: .public)
                        """)
                }
            }
            logErrors(of: context, id: record.id)
        } catch {
            Pipeline.log.error("ext: loading \(record.id, privacy: .public) failed: \(error, privacy: .public)")
        }
        Pipeline.signposter.endInterval("ext.load", state)
    }

    private func unload(id: String) {
        guard let context = contexts.removeValue(forKey: id) else { return }
        do {
            try controller.unload(context)
        } catch {
            Pipeline.log.error("ext: unloading \(id, privacy: .public) failed: \(error, privacy: .public)")
        }
    }

    private func logErrors(of context: WKWebExtensionContext, id: String) {
        guard !context.errors.isEmpty else { return }
        for error in context.errors {
            Pipeline.log.error("ext \(id, privacy: .public): \(error, privacy: .public)")
        }
    }

    func errorCount(for id: String) -> Int {
        contexts[id]?.errors.count ?? 0
    }

    func errors(for id: String) -> [String] {
        (contexts[id]?.errors ?? []).map(\.localizedDescription)
    }

    func loadedIcon(for id: String, size: CGFloat) -> NSImage? {
        contexts[id]?.webExtension.icon(for: CGSize(width: size, height: size))
            ?? iconCache[id]
    }

    func icon(for id: String) async -> NSImage? {
        if let cached = iconCache[id] {
            return cached
        }

        if let icon = contexts[id]?.webExtension.icon(for: CGSize(width: 32, height: 32)) {
            iconCache[id] = icon
            return icon
        }

        guard installed.contains(where: { $0.id == id }) else { return nil }

        do {
            let webExtension = try await WKWebExtension(resourceBaseURL: library.packageURL(for: id))
            let icon = webExtension.icon(for: CGSize(width: 32, height: 32))
            if let icon {
                iconCache[id] = icon
            }
            return icon
        } catch {
            Pipeline.log.error("ext: reading icon for \(id, privacy: .public) failed: \(error, privacy: .public)")
            return nil
        }
    }

    // MARK: - Install and manage

    func install(fromStoreID id: String) async {
        installState = .installing(id: id)
        do {
            let package = try await ChromeWebStore.downloadPackage(id: id)
            guard try await confirm(package, id: id) else {
                installState = .idle
                return
            }
            try await library.unpack(package, id: id)
            library.recordInstall(id: id)
            installed = library.records
            guard let record = installed.first(where: { $0.id == id }) else { return }
            await load(record)
            guard contexts[id] != nil else {
                uninstall(id: id)
                installState = .failed(
                    id: id,
                    message: String(localized: "This extension isn’t supported by WebKit")
                )
                return
            }
            installState = .installed(id: id)
            Pipeline.log.notice("ext: installed \(id, privacy: .public) from the Chrome Web Store")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            installState = .failed(id: id, message: message)
            Pipeline.log.error("ext: install of \(id, privacy: .public) failed: \(error, privacy: .public)")
        }
    }

    private func confirm(_ package: Data, id: String) async throws -> Bool {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("linen-ext-\(id).zip")
        try package.write(to: scratch, options: .atomic)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let webExtension = try await WKWebExtension(resourceBaseURL: scratch)
        return await ExtensionConsent.confirmInstall(
            name: webExtension.displayName ?? id,
            permissions: webExtension.requestedPermissions,
            matchPatterns: webExtension.allRequestedMatchPatterns,
            in: NSApp.keyWindow ?? NSApp.mainWindow
        )
    }

    func setEnabled(_ enabled: Bool, id: String) {
        library.setEnabled(enabled, id: id)
        installed = library.records
        if enabled {
            guard let record = installed.first(where: { $0.id == id }) else { return }
            Task { await load(record) }
        } else {
            unload(id: id)
        }
    }

    func uninstall(id: String) {
        unload(id: id)
        library.uninstall(id: id)
        installed = library.records
        anchors[id] = nil
        iconCache[id] = nil
        Pipeline.log.notice("ext: uninstalled \(id, privacy: .public)")
    }

    func isInstalled(_ id: String) -> Bool {
        installed.contains { $0.id == id }
    }

    // MARK: - Actions and popups

    var actionableExtensions: [InstalledExtension] {
        installed.filter { $0.enabled && contexts[$0.id] != nil }
    }

    var pinnedExtensions: [InstalledExtension] {
        actionableExtensions.filter(\.isPinned)
    }

    var unpinnedExtensions: [InstalledExtension] {
        actionableExtensions.filter { !$0.isPinned }
    }

    func setPinned(_ pinned: Bool, id: String) {
        library.setPinned(pinned, id: id)
        installed = library.records
        if !pinned {
            anchors[id] = nil
        }
    }

    func move(_ id: String, before anchor: String?) {
        library.move(id, before: anchor)
        installed = library.records
    }

    func action(for id: String) -> WKWebExtension.Action? {
        guard let context = contexts[id] else { return nil }
        let tab = browser.activeTab.map { adapter(for: $0) }
        return context.action(for: tab)
    }

    func registerAnchor(_ view: NSView?, for id: String) {
        anchors[id] = view
    }

    func registerOverflowAnchor(_ view: NSView?) {
        overflowAnchor = view
    }

    private func anchorView(for id: String) -> NSView? {
        if let own = anchors[id], own.window != nil {
            return own
        }
        if let overflowAnchor, overflowAnchor.window != nil {
            return overflowAnchor
        }
        return nil
    }

    func performAction(for id: String) {
        guard let context = contexts[id] else { return }
        let tab = browser.activeTab.map { adapter(for: $0) }
        guard let action = context.action(for: tab) else { return }

        if let popover = presentedPopup, presentedPopupID == id, popover.isShown {
            popover.performClose(nil)
            return
        }
        if lastDismissedPopupID == id, Date().timeIntervalSince(lastPopupDismissal) < 0.3 {
            return
        }

        if action.presentsPopup {
            present(action, for: id)
        } else {
            context.performAction(for: tab)
        }
    }

    @discardableResult
    private func present(_ action: WKWebExtension.Action, for id: String) -> Bool {
        guard let popover = action.popupPopover, let anchor = anchorView(for: id) else {
            return false
        }
        popover.behavior = .transient
        if let popupCloseObserver {
            NotificationCenter.default.removeObserver(popupCloseObserver)
        }
        popupCloseObserver = NotificationCenter.default.addObserver(
            forName: NSPopover.didCloseNotification,
            object: popover,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.presentedPopup = nil
                self.presentedPopupID = nil
                self.lastDismissedPopupID = id
                self.lastPopupDismissal = Date()
            }
        }
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        reopenIfPageIsMissing(action, for: id)
        clipPopup(popover)
        presentedPopup = popover
        presentedPopupID = id
        action.hasUnreadBadgeText = false
        return true
    }

    private func reopenIfPageIsMissing(_ action: WKWebExtension.Action, for id: String) {
        Task {
            for _ in 0..<2 {
                try? await Task.sleep(for: .milliseconds(900))
                guard presentedPopupID == id, presentedPopup?.isShown == true,
                      action.popupWebView?.url == nil
                else { return }
            }

            guard reloadedForEmptyPopup.insert(id).inserted else {
                Pipeline.log.error("ext: \(id, privacy: .public) popup still empty after a reload")
                return
            }
            Pipeline.log.notice("ext: \(id, privacy: .public) popup page missing, reloading the extension")

            presentedPopup?.performClose(nil)
            presentedPopup = nil
            presentedPopupID = nil
            action.closePopup()

            guard let record = installed.first(where: { $0.id == id }) else { return }
            unload(id: id)
            await load(record)

            guard presentedPopupID == nil, let context = contexts[id] else { return }

            var waited = 0
            while anchors[id]?.window == nil, waited < 10 {
                try? await Task.sleep(for: .milliseconds(30))
                waited += 1
            }

            let tab = browser.activeTab.map { adapter(for: $0) }
            guard let fresh = context.action(for: tab), fresh.presentsPopup else { return }
            present(fresh, for: id)
        }
    }

    private func clipPopup(_ popover: NSPopover) {
        guard let content = popover.contentViewController?.view,
              let frameView = content.window?.contentView?.superview
        else { return }

        guard let radius = Self.plateCornerRadius(of: frameView) else {
            Pipeline.log.notice("""
                ext: popup left unclipped - \
                \(String(describing: type(of: frameView)), privacy: .public) \
                bounds \(NSStringFromRect(frameView.bounds), privacy: .public) \
                reports no plausible corner \
                (layer \(frameView.layer?.cornerRadius ?? -1, privacy: .public))
                """)
            return
        }

        content.wantsLayer = true
        content.layer?.cornerRadius = radius
        content.layer?.cornerCurve = .continuous
        content.layer?.masksToBounds = true
        Pipeline.log.notice("ext: popup clipped to the plate's \(radius, privacy: .public)pt corner")
    }

    private static func plateCornerRadius(of frameView: NSView) -> CGFloat? {
        let limit = min(frameView.bounds.width, frameView.bounds.height) / 4
        guard limit > 1 else { return nil }

        for key in ["cornerRadius", "_cornerRadius"] {
            guard frameView.responds(to: NSSelectorFromString(key)),
                  let radius = frameView.value(forKey: key) as? CGFloat,
                  radius > 1, radius <= limit
            else { continue }
            return radius
        }
        if let radius = frameView.layer?.cornerRadius, radius > 1, radius <= limit {
            return radius
        }
        return nil
    }

    func contextMenu(for id: String) -> NSMenu? {
        guard let context = contexts[id] else { return nil }
        let tab = browser.activeTab.map { adapter(for: $0) }
        let menu = NSMenu()

        for item in context.action(for: tab)?.menuItems ?? [] {
            item.menu?.removeItem(item)
            menu.addItem(item)
        }
        if !menu.items.isEmpty {
            menu.addItem(.separator())
        }

        let isPinned = installed.first { $0.id == id }?.isPinned ?? true
        let pinTitle: LocalizedStringResource = isPinned ? "Hide Extension" : "Show Extension"
        menu.addItem(appMenuItem(
            title: String(localized: pinTitle),
            action: #selector(togglePinnedFromMenu(_:)),
            id: id
        ))
        if context.optionsPageURL != nil {
            menu.addItem(appMenuItem(
                title: String(localized: "Extension Options"),
                action: #selector(openOptionsFromMenu(_:)),
                id: id
            ))
        }

        menu.addItem(.separator())
        menu.addItem(appMenuItem(
            title: String(localized: "Remove Extension"),
            action: #selector(removeFromMenu(_:)),
            id: id
        ))
        return menu
    }

    private func appMenuItem(title: String, action: Selector, id: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = id
        return item
    }

    @objc private func togglePinnedFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let record = installed.first(where: { $0.id == id }) else { return }
        setPinned(!record.isPinned, id: id)
    }

    @objc private func openOptionsFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let context = contexts[id] else { return }
        _ = onOpenTab?(context.optionsPageURL)
    }

    @objc private func removeFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        confirmUninstall(id: id)
    }

    func hasOptionsPage(id: String) -> Bool {
        contexts[id]?.optionsPageURL != nil
    }

    func openOptionsPage(id: String) {
        guard let url = contexts[id]?.optionsPageURL else { return }
        _ = onOpenTab?(url)
    }

    func confirmUninstall(id: String) {
        let name = installed.first { $0.id == id }?.displayName ?? id
        let alert = NSAlert()
        alert.messageText = String(localized: "Remove “\(name)”?")
        alert.informativeText = String(localized: "Its settings and data are removed too.")
        if let icon = loadedIcon(for: id, size: 64) {
            alert.icon = icon
        }
        alert.addButton(withTitle: String(localized: "Remove Extension"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        uninstall(id: id)
    }

    // MARK: - WKWebExtensionControllerDelegate

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
        actionRevision += 1
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
