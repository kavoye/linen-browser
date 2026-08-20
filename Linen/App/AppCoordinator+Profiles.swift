// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

extension AppCoordinator {
    // MARK: - Profiles

    func switchProfile(to profile: Profile) async {
        await profileSwitches.run { [weak self] in
            await self?.performProfileSwitch(to: profile)
        }
    }

    private func performProfileSwitch(to profile: Profile) async {
        guard profile.id != profiles.current.id else { return }
        isSwitchingProfile = true
        defer { isSwitchingProfile = false }

        voiceInput.cancel()
        agentTurns.cancel()
        media.releaseControl()
        statusMessage = nil
        closePalette()

        browser.closeAllTabs()
        applyProfileStores(profile)
        profiles.markCurrent(profile)

        await extensions.adopt(profile: profile.isPrivate ? nil : profile)
        WebViewPool.shared.installExtensionController(extensions.controller)

        browser.restoreSession(force: true)
        conversationLog.retainTabs(Set(browser.tabs.map(\.id)))
        browser.ensureActiveTab()
        showBrowserPage()
        show(notice: profile.name)
        Pipeline.log.notice("profile: switched (private: \(profile.isPrivate, privacy: .public))")
    }

    func enterPrivateBrowsing() {
        guard !profiles.isPrivate else {
            openNewTab()
            return
        }
        Task { await switchProfile(to: profiles.privateBrowsing) }
    }

    func leavePrivateBrowsing() {
        guard profiles.isPrivate || privateSession != nil else { return }
        Task {
            if profiles.isPrivate {
                await switchProfile(to: profiles.profileToReturnTo)
            }
            await endPrivateSession()
        }
    }

    func applyProfileStores(_ profile: Profile) {
        let database: AppDatabase
        if profile.isPrivate {
            let session = privateSession ?? PrivateBrowsingSession(
                database: profile.makeDatabase(),
                dataStore: profile.makeDataStore()
            )
            privateSession = session
            database = session.database
            WebViewPool.shared.useDataStore(session.dataStore)
        } else {
            database = profile.makeDatabase()
            WebViewPool.shared.useDataStore(profile.makeDataStore())
        }
        let sitePermissions = SitePermissions.use(file: profile.permissionsFile)
        browser.adopt(
            database: database,
            sitePermissions: sitePermissions,
            privately: profile.isPrivate
        )
        conversationLog.adopt(database: database)
        PageZoomStore.use(file: profile.zoomFile)
        applyProfileSettings(profile)
        FaviconLoader.shared.persistsToDisk = !profile.isPrivate
        settings.forcesDarkAppearance = profile.isPrivate
    }

    private func applyProfileSettings(_ profile: Profile) {
        let owner = profile.isPrivate ? profiles.profileToReturnTo : profile
        let defaults = ProfileSettingsStore.defaults(for: owner)

        settings.useSessionDefaults(defaults)
        LLMSettings.defaults = defaults
        ContentBlocker.shared.use(defaults: defaults)
        AgentActionPolicy.use(storage: defaults)
        FaviconLoader.shared.use(cacheDirectory: FaviconLoader.cacheDirectory(for: owner))
        configureEngines()
    }

    private func endPrivateSession() async {
        guard privateSession != nil else { return }
        privateSession = nil
        FaviconLoader.shared.forgetSessionOnlyIcons()
        await Profile.erase(profiles.privateBrowsing)
        Pipeline.log.notice("profile: private session ended")
    }

    func windowDidClose() async {
        if profiles.isPrivate {
            await switchProfile(to: profiles.profileToReturnTo)
        }
        await endPrivateSession()
    }
}
