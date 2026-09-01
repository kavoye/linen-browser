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
    private(set) var systemExtensions: [InstalledExtension] = []
    private(set) var contexts: [String: WKWebExtensionContext] = [:]
    private(set) var actionRevision = 0
    var installState: StoreInstallState = .idle
    var updateChecks: [String: UpdateCheck] = [:]

    @ObservationIgnored private static var systemCatalogue: [SafariExtension]?

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
    @ObservationIgnored private var backgroundStarts: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let nativeMessaging = NativeMessagingService()
    private(set) var appsOutOfReach: Set<String> = []

    init(browser: BrowserModel, library: ExtensionLibrary = ExtensionLibrary()) {
        self.browser = browser
        self.library = library
        controller = WKWebExtensionController(configuration: Self.controllerConfiguration(for: nil))
        super.init()
        controller.delegate = self
        nativeMessaging.geckoID = { [weak self] id in
            guard let self else { return nil }
            return NativeMessagingManifest.geckoID(inPackage: self.library.packageURL(for: id))
        }

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
        library = ExtensionLibrary(profile: profile)
        controller = WKWebExtensionController(configuration: Self.controllerConfiguration(for: profile))
        controller.delegate = self
    }

    enum Storage: Equatable {
        case shared
        case persistent(UUID)
        case ephemeral
    }

    static func storageIdentifier(for profile: Profile?) -> Storage {
        guard let profile else { return .shared }
        if profile.isPrivate {
            return .ephemeral
        }
        return profile.isOriginal ? .shared : .persistent(profile.id)
    }

    static func eraseData(for profile: Profile) async {
        guard !profile.isOriginal, !profile.isPrivate else { return }
        let library = ExtensionLibrary(profile: profile)
        library.load()
        let ids = library.records.map(\.id)
        library.forgetThisProfile()
        guard !ids.isEmpty else { return }

        let controller = WKWebExtensionController(configuration: controllerConfiguration(for: profile))
        let types: Set<WKWebExtension.DataType> = [.local, .session, .synchronized]
        var cleared = 0
        for id in ids {
            guard let webExtension = try? await WKWebExtension(
                resourceBaseURL: library.packageURL(for: id)
            ) else { continue }
            let context = WKWebExtensionContext(for: webExtension)
            context.uniqueIdentifier = id
            guard let record = await controller.dataRecord(ofTypes: types, for: context) else { continue }
            await controller.removeData(ofTypes: types, from: [record])
            cleared += 1
        }
        Pipeline.log.notice("ext: cleared \(cleared, privacy: .public) stores for a removed profile")
    }

    private static func controllerConfiguration(
        for profile: Profile?
    ) -> WKWebExtensionController.Configuration {
        let configuration: WKWebExtensionController.Configuration
        switch storageIdentifier(for: profile) {
        case .shared:
            configuration = .default()
        case .persistent(let identifier):
            configuration = .init(identifier: identifier)
        case .ephemeral:
            configuration = .nonPersistent()
        }
        configuration.webViewConfiguration.applicationNameForUserAgent = WebViewPool.safariApplicationName
        return configuration
    }

    func beginAdopting(profile: Profile?) {
        for (_, context) in contexts {
            try? controller.unload(context)
        }
        contexts = [:]
        appsOutOfReach = []
        anchors = [:]
        reloadedForEmptyPopup = []
        presentedPopup?.performClose(nil)
        presentedPopup = nil
        presentedPopupID = nil

        controller = WKWebExtensionController(configuration: Self.controllerConfiguration(for: profile))
        controller.delegate = self
        guard let profile else { return }
        library = ExtensionLibrary(profile: profile)
    }

    func start() async {
        library.load()
        installed = library.records
        await discoverSystemExtensions()

        if let windowAdapter {
            controller.didOpenWindow(windowAdapter)
            controller.didFocusWindow(windowAdapter)
        }

        for record in installed + systemExtensions where record.enabled {
            await load(record)
        }
    }

    func discoverSystemExtensions() async {
        let found: [SafariExtension]
        if let known = Self.systemCatalogue {
            found = known
        } else {
            found = await Task.detached(priority: .utility) {
                SafariExtensionCatalog.installed()
            }.value
            Self.systemCatalogue = found
        }
        systemExtensions = found.map { extensionBundle in
            let placement = library.placement(for: extensionBundle.id)
            return InstalledExtension(
                id: extensionBundle.id,
                displayName: extensionBundle.displayName,
                version: extensionBundle.version,
                enabled: placement.enabled,
                installedAt: Date(timeIntervalSinceReferenceDate: 0),
                isPinned: placement.isPinned,
                toolbarOrder: placement.toolbarOrder,
                bundlePath: extensionBundle.bundlePath
            )
        }
        Pipeline.log.notice("ext: found \(found.count, privacy: .public) Safari extensions on this Mac")
    }

    private func record(for id: String) -> InstalledExtension? {
        installed.first { $0.id == id } ?? systemExtensions.first { $0.id == id }
    }

    private func load(_ record: InstalledExtension) async {
        guard contexts[record.id] == nil else { return }
        let state = Pipeline.signposter.beginInterval("ext.load")
        let started = ContinuousClock.now
        do {
            let webExtension: WKWebExtension
            if let path = record.bundlePath, let bundle = Bundle(path: path) {
                webExtension = try await WKWebExtension(appExtensionBundle: bundle)
            } else {
                let package = library.packageURL(for: record.id)
                ExtensionShims.ensureApplied(at: package)
                webExtension = try await WKWebExtension(resourceBaseURL: package)
            }
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
            if !record.isSystem {
                library.updateMetadata(
                    id: record.id,
                    name: webExtension.displayName,
                    version: webExtension.version
                )
                installed = library.records
            }

            let name = webExtension.displayName ?? record.displayName
            let ms = (ContinuousClock.now - started).milliseconds
            Pipeline.log.notice("ext: loaded \(name, privacy: .public) in \(ms) ms")

            if webExtension.hasBackgroundContent {
                startBackgroundContent(of: context, id: record.id, name: name)
            }
            logErrors(of: context, id: record.id)
        } catch {
            Pipeline.log.error("ext: loading \(record.id, privacy: .public) failed: \(error, privacy: .public)")
        }
        Pipeline.signposter.endInterval("ext.load", state)
    }

    private func startBackgroundContent(of context: WKWebExtensionContext, id: String, name: String) {
        backgroundStarts.removeValue(forKey: id)?.cancel()
        let watchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            Pipeline.log.error("ext: \(name, privacy: .public) background never started")
            self?.logErrors(of: context, id: id)
        }
        backgroundStarts[id] = Task { @MainActor [weak self] in
            defer { watchdog.cancel() }
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
            self?.logErrors(of: context, id: id)
        }
    }

    private func refuseReachingApp(for context: WKWebExtensionContext) -> NSError {
        let id = context.uniqueIdentifier
        if appsOutOfReach.insert(id).inserted {
            Pipeline.log.notice("ext: \(id, privacy: .public) wanted its own app, which Linen cannot reach")
        }
        return NSError(
            domain: WKWebExtensionContext.errorDomain,
            code: WKWebExtensionContext.Error.unknown.rawValue,
            userInfo: [NSLocalizedDescriptionKey: Self.appOutOfReachReason]
        )
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        sendMessage message: Any,
        toApplicationWithIdentifier applicationIdentifier: String?,
        for context: WKWebExtensionContext,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        let handled = nativeMessaging.sendOnce(
            message: message,
            applicationIdentifier: applicationIdentifier,
            for: context,
            reply: replyHandler
        )
        guard !handled else { return }
        replyHandler(nil, refuseReachingApp(for: context))
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        connectUsing port: WKWebExtension.MessagePort,
        for context: WKWebExtensionContext,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        switch nativeMessaging.connect(port: port, for: context) {
        case .connected:
            completionHandler(nil)
        case .failed(let error):
            completionHandler(error)
        case .unavailable:
            completionHandler(refuseReachingApp(for: context))
        }
    }

    private func unload(id: String) {
        backgroundStarts.removeValue(forKey: id)?.cancel()
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
        errors(for: id).count
    }

    func errors(for id: String) -> [String] {
        var found = (contexts[id]?.errors ?? []).map(\.localizedDescription)
        if appsOutOfReach.contains(id) {
            found.append(Self.appOutOfReachReason)
        }
        return found
    }

    static let appOutOfReachReason = String(
        localized: "This extension asked to talk to its own app. Linen can’t reach it, so the parts that need it won’t work."
    )

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

        guard let known = record(for: id) else { return nil }

        do {
            let webExtension: WKWebExtension
            if let path = known.bundlePath, let bundle = Bundle(path: path) {
                webExtension = try await WKWebExtension(appExtensionBundle: bundle)
            } else {
                webExtension = try await WKWebExtension(resourceBaseURL: library.packageURL(for: id))
            }
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

    func install(id: String, from store: ExtensionStore) async {
        installState = .installing(id: id)
        do {
            let package: Data
            switch store {
            case .chrome:
                package = try await ChromeWebStore.downloadPackage(id: id)
            case .firefox:
                package = try await FirefoxAddons.downloadPackage(slug: id)
            }
            try await library.unpack(package, id: id)
            guard try await confirm(package, id: id) else {
                library.discardPackage(id: id)
                installState = .idle
                return
            }
            library.recordInstall(id: id, source: store)
            installed = library.records
            guard let record = installed.first(where: { $0.id == id }) else {
                installState = .failed(
                    id: id,
                    message: String(localized: "This extension couldn’t be added to your library")
                )
                return
            }
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
            Pipeline.log.notice("""
                ext: installed \(id, privacy: .public) from the \
                \(store.rawValue, privacy: .public) store
                """)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            installState = .failed(id: id, message: message)
            Pipeline.log.error("ext: install of \(id, privacy: .public) failed: \(error, privacy: .public)")
        }
    }

    func replacePackage(_ package: Data, id: String, name: String?, version: String) async throws {
        unload(id: id)
        try await library.unpack(package, id: id)
        library.updateMetadata(id: id, name: name, version: version)
        installed = library.records
        guard let refreshed = record(for: id), refreshed.enabled else { return }
        await load(refreshed)
    }

    func grantedPermissions(id: String) -> Set<String> {
        Set(contexts[id]?.webExtension.requestedPermissions.map(\.rawValue) ?? [])
    }

    func installedRecord(id: String) -> InstalledExtension? {
        record(for: id)
    }

    private func confirm(_ package: Data, id: String) async throws -> Bool {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("linen-ext-\(id).zip")
        try package.write(to: scratch, options: .atomic)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let webExtension = try await WKWebExtension(resourceBaseURL: scratch)
        let unpacked = library.packageURL(for: id)
        let accepted = Set(webExtension.requestedPermissions.map(\.rawValue))
        let unsupported = await Task.detached(priority: .userInitiated) {
            ExtensionCompatibility.report(forPackageAt: unpacked, accepting: accepted)
        }.value
        if !unsupported.isEmpty {
            let names = unsupported.names.joined(separator: ", ")
            Pipeline.log.notice("ext: \(id, privacy: .public) needs \(names, privacy: .public)")
        }
        return await ExtensionConsent.confirmInstall(
            name: webExtension.displayName ?? id,
            permissions: webExtension.requestedPermissions,
            matchPatterns: webExtension.allRequestedMatchPatterns,
            unsupported: unsupported,
            in: NSApp.keyWindow ?? NSApp.mainWindow
        )
    }

    func setEnabled(_ enabled: Bool, id: String) {
        library.setEnabled(enabled, id: id)
        installed = library.records
        applyPlacementsToSystemExtensions()
        if enabled {
            guard let record = record(for: id) else { return }
            Task { await load(record) }
        } else {
            unload(id: id)
        }
    }

    private func applyPlacementsToSystemExtensions() {
        systemExtensions = systemExtensions.map { record in
            var updated = record
            let placement = library.placement(for: record.id)
            updated.enabled = placement.enabled
            updated.isPinned = placement.isPinned
            updated.toolbarOrder = placement.toolbarOrder
            return updated
        }
    }

    func uninstall(id: String) {
        guard record(for: id)?.isSystem != true else { return }
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
        (installed + systemExtensions).filter { $0.enabled && contexts[$0.id] != nil }
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
        applyPlacementsToSystemExtensions()
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

        let known = record(for: id)
        let isPinned = known?.isPinned ?? true
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
        if known?.isSystem == true {
            menu.addItem(appMenuItem(
                title: String(localized: "Disable Extension"),
                action: #selector(disableFromMenu(_:)),
                id: id
            ))
        } else {
            menu.addItem(appMenuItem(
                title: String(localized: "Remove Extension"),
                action: #selector(removeFromMenu(_:)),
                id: id
            ))
        }
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
              let record = record(for: id) else { return }
        setPinned(!record.isPinned, id: id)
    }

    @objc private func disableFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        setEnabled(false, id: id)
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
        alert.informativeText = String(localized: "It is removed from every profile, along with its settings and data.")
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
