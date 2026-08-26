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
        switchingTo = profile
        defer { switchingTo = nil }

        var timing = ProfileSwitchTiming()

        voiceInput.cancel()
        agentTurns.cancel()
        agentTurns.forgetEveryConversation()
        researchPreview.forget()
        media.releaseControl()
        statusMessage = nil
        closePalette()
        timing.mark("quiesce")

        browser.saveBlocking()
        timing.mark("save session")

        browser.closeAllTabs(saving: false)
        timing.mark("close tabs")

        let database = profile.isPrivate ? nil : profile.makeDatabase()
        timing.mark("open database")

        applyProfileStores(profile, database: database)
        profiles.markCurrent(profile)
        timing.mark("adopt stores")

        extensions.beginAdopting(profile: profile)
        WebViewPool.shared.installExtensionController(extensions.controller)
        timing.mark("extensions")

        browser.restoreSession()
        retainAgentMemory()
        browser.ensureActiveTab()
        timing.mark("restore session")

        show(notice: profile.name)
        timing.log(isPrivate: profile.isPrivate)

        await extensions.start()
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

    func applyProfileStores(_ profile: Profile, database prepared: AppDatabase? = nil) {
        let database: AppDatabase
        if profile.isPrivate {
            let session = privateSession ?? PrivateBrowsingSession(
                database: prepared ?? profile.makeDatabase(),
                dataStore: profile.makeDataStore()
            )
            privateSession = session
            database = session.database
            WebViewPool.shared.useDataStore(session.dataStore)
        } else {
            database = prepared ?? profile.makeDatabase()
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
        browser.downloads.forgetPrivateDownloads()
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

private struct ProfileSwitchTiming {
    private let start = ContinuousClock.now
    private var last = ContinuousClock.now
    private var phases: [String] = []

    mutating func mark(_ phase: String) {
        let now = ContinuousClock.now
        phases.append("\(phase) \(Self.milliseconds(from: last, to: now))ms")
        last = now
    }

    func log(isPrivate: Bool) {
        let total = Self.milliseconds(from: start, to: .now)
        let detail = phases.joined(separator: ", ")
        Pipeline.log.notice("profile: switched in \(total, privacy: .public)ms, private \(isPrivate, privacy: .public) — \(detail, privacy: .public)")
    }

    private static func milliseconds(
        from: ContinuousClock.Instant,
        to: ContinuousClock.Instant
    ) -> Int {
        let elapsed = (to - from).components
        return Int(elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000)
    }
}
