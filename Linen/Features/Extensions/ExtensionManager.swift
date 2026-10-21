// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Observation
import os
import WebKit

@MainActor
@Observable
final class ExtensionManager: NSObject, WKWebExtensionControllerDelegate {
    private(set) var controller: WKWebExtensionController

    private(set) var installed: [InstalledExtension] = [] {
        didSet { PasswordAutofill.shared.refreshPolicy() }
    }
    private(set) var systemExtensions: [InstalledExtension] = [] {
        didSet { PasswordAutofill.shared.refreshPolicy() }
    }
    private(set) var contexts: [String: WKWebExtensionContext] = [:]
    private var wakingBackgrounds: Set<String> = []
    @ObservationIgnored private var loading: [String: UUID] = [:]
    private(set) var actionRevision = 0
    var installState: StoreInstallState = .idle
    var updateChecks: [String: UpdateCheck] = [:]
    var heldUpdates: [String: String] = ExtensionManager.savedHeldUpdates()

    @ObservationIgnored private static var systemCatalogue: [SafariExtension]?
    @ObservationIgnored private static let liveManagers = NSHashTable<ExtensionManager>.weakObjects()

    /// The application owns window creation; the complete configuration includes all URLs and moved tabs.
    var onOpenWindow: ((WKWebExtension.WindowConfiguration) -> ExtensionWindowAdapter?)?
    @ObservationIgnored var onManageExtensions: ((BrowserModel?) -> Void)?

    private var library: ExtensionLibrary
    private(set) var profile: Profile?

    @ObservationIgnored var windows: [ObjectIdentifier: ExtensionWindowAdapter] = [:]
    @ObservationIgnored var windowOrder: [ObjectIdentifier] = []
    @ObservationIgnored weak var lastFocusedWindow: ExtensionWindowAdapter?
    @ObservationIgnored private var startupTask: Task<Void, Never>?
    @ObservationIgnored var hasStarted = false
    @ObservationIgnored private var isStopped = false

    @ObservationIgnored var tabAdapters: [UUID: ExtensionTabAdapter] = [:]
    @ObservationIgnored private let icons = ExtensionIcons()
    @ObservationIgnored let popups = ExtensionPopups()

    @ObservationIgnored private var backgroundStarts: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let nativeMessaging = NativeMessagingService()
    private(set) var appsOutOfReach: Set<String> = []

    init(profile: Profile? = nil, dataStore: WKWebsiteDataStore? = nil, library: ExtensionLibrary? = nil) {
        self.profile = profile
        self.library = library ?? profile.map { ExtensionLibrary(profile: $0) } ?? ExtensionLibrary()
        controller = WKWebExtensionController(configuration: Self.controllerConfiguration(for: profile, dataStore: dataStore))
        super.init()
        Self.liveManagers.add(self)
        controller.delegate = self
        nativeMessaging.geckoID = { [weak self] id in
            guard let self else { return nil }
            return NativeMessagingManifest.geckoID(inPackage: self.library.packageURL(for: id))
        }
    }

    convenience init(browser: BrowserModel, library: ExtensionLibrary = ExtensionLibrary()) {
        self.init(library: library)
        register(browser: browser)
    }

    func didUnregister(browser: BrowserModel, window: ExtensionWindowAdapter) {
        popups.forget(browser, window: window)
        if windows.isEmpty, profile?.isPrivate == true {
            isStopped = true
            startupTask?.cancel()
            for task in backgroundStarts.values {
                task.cancel()
            }
            backgroundStarts.removeAll()
            for id in Array(contexts.keys) {
                unload(id: id)
            }
            popups.close()
            onOpenWindow = nil
        }
    }

    func wakeBackgrounds(for url: URL) {
        for (id, context) in contexts {
            let webExtension = context.webExtension
            guard webExtension.hasBackgroundContent, !webExtension.hasPersistentBackgroundContent,
                  !wakingBackgrounds.contains(id),
                  webExtension.allRequestedMatchPatterns.contains(where: { $0.matches(url) })
            else { continue }
            wakingBackgrounds.insert(id)
            Task { [weak self] in
                try? await context.loadBackgroundContent()
                self?.wakingBackgrounds.remove(id)
            }
        }
    }

    // MARK: - Lifecycle

    func useLibrary(for profile: Profile) {
        self.profile = profile
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
        for profile: Profile?, dataStore: WKWebsiteDataStore? = nil
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
        if let dataStore {
            configuration.webViewConfiguration.websiteDataStore = dataStore
        }
        configuration.webViewConfiguration.applicationNameForUserAgent = WebViewPool.safariApplicationName
        return configuration
    }

    func beginAdopting(profile: Profile?) {
        self.profile = profile
        startupTask?.cancel()
        startupTask = nil
        hasStarted = false
        isStopped = false
        loading.removeAll()
        for (_, context) in contexts {
            try? controller.unload(context)
        }
        contexts = [:]
        appsOutOfReach = []
        popups.reset()

        controller = WKWebExtensionController(configuration: Self.controllerConfiguration(for: profile))
        controller.delegate = self
        guard let profile else { return }
        library = ExtensionLibrary(profile: profile)
    }

    func start() async {
        if let startupTask {
            await startupTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            library.load()
            installed = library.records
            await discoverSystemExtensions()
            guard !Task.isCancelled else { return }
            hasStarted = true
            for window in windowAdapters {
                controller.didOpenWindow(window)
            }
            controller.didFocusWindow(focusedWindowAdapter)
            for record in installed + systemExtensions where record.enabled {
                guard !Task.isCancelled else { return }
                await load(record)
            }
        }
        startupTask = task
        await task.value
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
            var record = InstalledExtension(
                id: extensionBundle.id,
                displayName: extensionBundle.displayName,
                version: extensionBundle.version,
                enabled: placement.enabled,
                installedAt: Date(timeIntervalSinceReferenceDate: 0),
                isPinned: placement.isPinned,
                toolbarOrder: placement.toolbarOrder,
                bundlePath: extensionBundle.bundlePath
            )
            record.blockedHosts = placement.blockedHosts
            return record
        }
        Pipeline.log.notice("ext: found \(found.count, privacy: .public) Safari extensions on this Mac")
    }

    func record(for id: String) -> InstalledExtension? {
        installed.first { $0.id == id } ?? systemExtensions.first { $0.id == id }
    }

    private func load(_ record: InstalledExtension) async {
        guard !isStopped, contexts[record.id] == nil, loading[record.id] == nil else { return }
        let generation = UUID()
        loading[record.id] = generation
        defer {
            if loading[record.id] == generation {
                loading[record.id] = nil
            }
        }
        let state = Pipeline.signposter.beginInterval("ext.load")
        defer { Pipeline.signposter.endInterval("ext.load", state) }
        let started = ContinuousClock.now
        do {
            let webExtension: WKWebExtension
            if let path = record.bundlePath, let bundle = Bundle(path: path) {
                webExtension = try await WKWebExtension(appExtensionBundle: bundle)
            } else {
                let package = library.packageURL(for: record.id)
                ExtensionShims.ensureApplied(at: package)
                ExtensionShims.ensurePagesApplied(at: package)
                ExtensionExternalConnect.ensureRelayApplied(at: package)
                ExtensionPageAssets.ensureReporterApplied(at: package)
                webExtension = try await WKWebExtension(resourceBaseURL: package)
            }
            if let icon = webExtension.icon(for: CGSize(width: 32, height: 32)) {
                icons.store(icon, for: record.id)
            }
            guard !isStopped, !Task.isCancelled, loading[record.id] == generation,
                  contexts[record.id] == nil else { return }
            let context = WKWebExtensionContext(for: webExtension)
            context.hasAccessToPrivateData = profile?.isPrivate == true
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
            for host in record.blockedHosts {
                if let pattern = ExtensionSiteAccess.websitePattern(for: host) {
                    context.setPermissionStatus(.deniedExplicitly, for: pattern)
                }
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
            Pipeline.log.notice("ext: \(name, privacy: .public) [\(record.id, privacy: .public)] loaded in \(ms)ms")

            if webExtension.hasBackgroundContent {
                startBackgroundContent(of: context, id: record.id, name: name)
            }
            logErrors(of: context, id: record.id)
        } catch {
            Self.logFailure(error, id: record.id, name: record.displayName, operation: "loading")
        }
    }

    private func startBackgroundContent(of context: WKWebExtensionContext, id: String, name: String) {
        backgroundStarts.removeValue(forKey: id)?.cancel()
        let watchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            Pipeline.log.error("ext: \(name, privacy: .public) [\(id, privacy: .public)] background start timed out")
            self?.logErrors(of: context, id: id)
        }
        backgroundStarts[id] = Task { @MainActor [weak self] in
            defer { watchdog.cancel() }
            do {
                try await context.loadBackgroundContent()
                Pipeline.log.notice("ext: \(name, privacy: .public) [\(id, privacy: .public)] background ready")
            } catch {
                Self.logFailure(error, id: id, name: name, operation: "starting background")
            }
            self?.logErrors(of: context, id: id)
        }
    }

    private func refuseReachingApp(for context: WKWebExtensionContext) -> NSError {
        let id = context.uniqueIdentifier
        if appsOutOfReach.insert(id).inserted {
            Pipeline.log.notice("Extension runtime event")
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
        loading[id] = nil
        backgroundStarts.removeValue(forKey: id)?.cancel()
        guard let context = contexts.removeValue(forKey: id) else { return }
        do {
            try controller.unload(context)
        } catch {
            Pipeline.log.error("Extension unloading failed")
        }
    }

    private func logErrors(of context: WKWebExtensionContext, id: String) {
        let name = context.webExtension.displayName ?? record(for: id)?.displayName ?? id
        for error in context.errors {
            Self.logFailure(error, id: id, name: name, operation: "reported")
        }
    }

    private static func logFailure(_ error: any Error, id: String, name: String, operation: String) {
        let failure = error as NSError
        Pipeline.log.error("""
        ext: \(name, privacy: .public) [\(id, privacy: .public)] \(operation, privacy: .public): \
        \(failure.domain, privacy: .public) \(failure.code), \(failure.localizedDescription, privacy: .public)
        """)
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
        localized: "The extension’s companion app is unavailable. Features that require it won’t work."
    )

    func loadedIcon(for id: String, size: CGFloat) -> NSImage? {
        contexts[id]?.webExtension.icon(for: CGSize(width: size, height: size))
            ?? icons.cached(for: id)
    }

    func icon(for id: String) async -> NSImage? {
        await icons.icon(for: id, context: contexts[id], record: record(for: id), packageURL: library.packageURL(for: id))
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
            refreshSharedLibraries(for: id)
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
            Pipeline.log.notice("Extension installed")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            installState = .failed(id: id, message: message)
            Pipeline.log.error("Extension installation failed")
        }
    }

    func replacePackage(_ package: Data, id: String, name: String?, version: String) async throws {
        unload(id: id)
        try await library.unpack(package, id: id)
        library.updateMetadata(id: id, name: name, version: version)
        refreshSharedLibraries(for: id, reloadContexts: true)
        installed = library.records
        guard let refreshed = record(for: id), refreshed.enabled else { return }
        await load(refreshed)
    }

    func packageURL(for id: String) -> URL {
        library.packageURL(for: id)
    }

    func requestsAccess(id: String, to url: URL) -> Bool {
        contexts[id]?.webExtension.allRequestedMatchPatterns.contains { $0.matches(url) } == true
    }

    func blockingHost(id: String, for host: String) -> String? {
        record(for: id)?.blockedHosts.first { ExtensionSiteAccess.website(host, isCoveredBy: $0) }
    }

    func isBlocked(id: String, on host: String) -> Bool {
        blockingHost(id: id, for: host) != nil
    }

    func setAllowed(_ allowed: Bool, on host: String, id: String, reloading browser: BrowserModel? = nil) {
        library.setBlocked(!allowed, host: host, id: id)
        installed = library.records
        applyPlacementsToSystemExtensions()
        if let context = contexts[id], let pattern = ExtensionSiteAccess.websitePattern(for: host) {
            if allowed {
                context.setPermissionStatus(.unknown, for: pattern)
                for requested in context.webExtension.allRequestedMatchPatterns {
                    context.setPermissionStatus(.grantedExplicitly, for: requested)
                }
            } else {
                context.setPermissionStatus(.deniedExplicitly, for: pattern)
            }
        }
        for tab in browser?.tabs ?? [] where tab.isMaterialised {
            guard let website = ExtensionSiteAccess.website(of: URL(string: tab.urlString)),
                  ExtensionSiteAccess.website(website, isCoveredBy: host) else { continue }
            tab.reload()
        }
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
            Pipeline.log.notice("Extension requests unsupported capabilities")
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
            updated.blockedHosts = placement.blockedHosts
            return updated
        }
    }

    func uninstall(id: String) {
        guard record(for: id)?.isSystem != true else { return }
        unload(id: id)
        library.uninstall(id: id)
        refreshSharedLibraries(for: id, unloadContexts: true)
        installed = library.records
        popups.forgetAnchors(for: id)
        icons.forget(id)
        setHeldUpdate(nil, id: id)
        Pipeline.log.notice("Extension uninstalled")
    }

    /// Packages and the catalogue are shared, while enablement and runtime contexts belong to profiles.
    private func refreshSharedLibraries(for id: String, unloadContexts: Bool = false, reloadContexts: Bool = false) {
        let package = library.packageURL(for: id)
        for manager in Self.liveManagers.allObjects where manager !== self && manager.library.packageURL(for: id) == package {
            if unloadContexts || reloadContexts {
                manager.unload(id: id)
            }
            manager.library.refresh()
            manager.installed = manager.library.records
            manager.icons.forget(id)
            if reloadContexts, let record = manager.record(for: id), record.enabled {
                Task { await manager.load(record) }
            }
        }
    }

    func isInstalled(_ id: String) -> Bool {
        installed.contains { $0.id == id }
    }

    // MARK: - Actions and popups

    func noteActionUpdate() {
        actionRevision += 1
    }

    func setPinned(_ pinned: Bool, id: String) {
        library.setPinned(pinned, id: id)
        installed = library.records
        applyPlacementsToSystemExtensions()
        if !pinned {
            popups.forgetAnchors(for: id)
        }
    }

    func move(_ id: String, before anchor: String?) {
        library.move(id, before: anchor)
        installed = library.records
    }

    private func anchorView(for id: String, in browser: BrowserModel? = nil) -> NSView? {
        guard let browser = registeredWindow(in: browser)?.browser else { return nil }
        return popups.anchor(for: id, in: browser)
    }

    @discardableResult
    func present(_ action: WKWebExtension.Action, for id: String, in browser: BrowserModel? = nil) -> Bool {
        guard let window = registeredWindow(in: browser), let popover = action.popupPopover,
              let anchor = anchorView(for: id, in: window.browser) else {
            return false
        }
        popups.show(popover, for: id, in: window, at: anchor)
        reopenIfPageIsMissing(action, for: id, in: window)
        action.hasUnreadBadgeText = false
        return true
    }

    private func reopenIfPageIsMissing(_ action: WKWebExtension.Action, for id: String, in window: ExtensionWindowAdapter) {
        Task { [weak window] in
            guard let window, owns(window) else { return }
            for _ in 0..<2 {
                try? await Task.sleep(for: .milliseconds(900))
                guard owns(window), popups.isShowing(id, in: window),
                      action.popupWebView?.url == nil
                else { return }
            }

            guard popups.noteReloadForEmptyPage(id) else {
                Pipeline.log.error("ext operation failed")
                return
            }
            Pipeline.log.notice("Extension runtime event")

            popups.close()
            action.closePopup()

            guard let record = installed.first(where: { $0.id == id }) else { return }
            unload(id: id)
            await load(record)

            guard owns(window), popups.popupID == nil, let context = contexts[id] else { return }

            var waited = 0
            while anchorView(for: id, in: window.browser) == nil, waited < 10 {
                try? await Task.sleep(for: .milliseconds(30))
                guard owns(window) else { return }
                waited += 1
            }

            guard owns(window) else { return }
            let tab = window.browser?.activeTab.map { adapter(for: $0) }
            guard let fresh = context.action(for: tab), fresh.presentsPopup else { return }
            present(fresh, for: id, in: window.browser)
        }
    }
}
