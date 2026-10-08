// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

/// Shared persistent-profile services, or the services of one private window.
@MainActor
final class BrowserProfileContext {
    private static var persistent: [UUID: BrowserProfileContext] = [:]

    static func shared(for profile: Profile, settingsOwner: Profile? = nil) -> BrowserProfileContext {
        if !profile.isPrivate, let existing = persistent[profile.id] {
            return existing
        }
        let context = BrowserProfileContext(profile: profile, settingsOwner: settingsOwner)
        if !profile.isPrivate {
            persistent[profile.id] = context
        }
        return context
    }

    static func existing(for profileID: UUID) -> BrowserProfileContext? {
        persistent[profileID]
    }

    static func forget(_ profileID: UUID) {
        persistent[profileID] = nil
    }

    let profile: Profile
    let database: AppDatabase
    let dataStore: WKWebsiteDataStore
    let settings: BrowserSettings
    let modelSettings: LLMSettings
    let actionPolicy: AgentActionPolicy
    let sitePermissions: SitePermissions
    let pageZoom: PageZoomStore
    let contentBlocker: ContentBlocker
    let favicons: FaviconLoader
    let webViewPool: WebViewPool
    lazy var downloads = DownloadManager(
        file: profile.downloadsFile,
        persists: !profile.isPrivate && !AppDatabase.isRunningTests && AppDatabase.ownsSession
    )
    lazy var history = HistoryStore(database: database)
    lazy var tabArchive = TabArchive(database: database)
    lazy var conversationLog = ConversationLog(database: database)
    lazy var extensions = ExtensionManager(profile: profile, dataStore: dataStore)

    init(profile: Profile, settingsOwner: Profile? = nil) {
        self.profile = profile
        database = profile.makeDatabase()
        dataStore = profile.makeDataStore()
        let owner = profile.isPrivate ? (settingsOwner ?? .original()) : profile
        let defaults = ProfileSettingsStore.defaults(for: owner)
        modelSettings = LLMSettings(defaults: defaults)
        actionPolicy = AgentActionPolicy(storage: profile.isPrivate ? SessionAgentGrantStorage() : defaults)
        #if DEBUG
        settings = BrowserSettings(defaults: StageMode.defaults, sessionDefaults: defaults)
        #else
        settings = BrowserSettings(sessionDefaults: defaults)
        #endif
        sitePermissions = SitePermissions(storageURL: profile.permissionsFile, persists: !profile.isPrivate)
        pageZoom = PageZoomStore(file: profile.zoomFile, persists: !profile.isPrivate)
        contentBlocker = ContentBlocker(defaults: defaults, settings: settings, persists: !profile.isPrivate)
        favicons = FaviconLoader(cacheDirectory: FaviconLoader.cacheDirectory(for: owner))
        favicons.persistsToDisk = !profile.isPrivate
        if profile.isPrivate {
            favicons.schemeOverride = .dark
        }
        webViewPool = WebViewPool(dataStore: dataStore, settings: settings, contentBlocker: contentBlocker)
        settings.onContentBlockingChanged = { [weak contentBlocker] in contentBlocker?.refresh() }
    }

    func endPrivateSession() async {
        guard profile.isPrivate else { return }
        downloads.forgetPrivateDownloads()
        actionPolicy.revokeAll()
        await contentBlocker.endPrivateSession()
        favicons.forgetSessionOnlyIcons()
        await dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }
}
