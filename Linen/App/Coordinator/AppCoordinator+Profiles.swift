// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

extension AppCoordinator {
    // MARK: - Profiles

    func switchProfile(
        to profile: Profile,
        landingIn spaceID: UUID? = nil,
        onCommit: (() -> Void)? = nil
    ) async {
        guard !isClosed else { return }
        if profile.isPrivate {
            requestNewWindow(isPrivate: true)
            return
        }
        await profileSwitches.run { [weak self] in
            await self?.performProfileSwitch(to: profile, landingIn: spaceID, onCommit: onCommit)
        }
    }

    private func performProfileSwitch(to profile: Profile, landingIn spaceID: UUID?, onCommit: (() -> Void)?) async {
        guard !isClosed, profile.id != profiles.current.id else { return }
        switchingTo = profile
        mcpServer.disconnect(browser: browser)
        defer {
            switchingTo = nil
        }

        var timing = ProfileSwitchTiming()

        voiceConversation.session?.stop()
        voiceConversation.session = nil
        voiceInput.cancel()
        agentTurns.cancel()
        agentTurns.forgetEveryConversation()
        media.releaseControl()
        statusMessage = nil
        closePalette()
        timing.mark("quiesce")

        let outgoing = browser
        let incoming = tabModel(for: profile)
        onCommit?()
        outgoing.markSessionClosed()
        closePeekImmediately()
        extensions.unregister(browser: outgoing)
        outgoing.cancelTabSwitching()
        if profiles.isPrivate {
            outgoing.downloads.forgetPrivateDownloads()
            outgoing.closeAllTabs(saving: false)
            let context = outgoing.context
            if let application {
                application.endPrivateSession(context)
            } else {
                Task { await context.endPrivateSession() }
            }
        } else {
            park(outgoing)
        }
        parkedModels[profile.id] = nil
        timing.mark("park")

        show(incoming)
        applyProfileStores(profile)
        profiles.markCurrent(profile)
        application?.configureExtensions(extensions, profile: profile)
        timing.mark("adopt stores")

        extensions.register(browser: incoming, window: nativeWindow)
        configureWindowCallbacks()
        prepareWindowWebServices()
        followSettings()
        updateWindowAppearance()
        timing.mark("extensions")

        if let spaceID {
            spaceSlider.land(in: spaceID)
        }
        incoming.reopenSession()
        retainAgentMemory()
        incoming.ensureActiveTab()
        timing.mark("show")

        if spaceID == nil {
            notice.show(profile.name)
        }
        timing.log(isPrivate: profile.isPrivate)

        await extensions.start()
    }

    func enterPrivateBrowsing() {
        requestNewWindow(isPrivate: true)
    }

    func applyProfileStores(_ profile: Profile) {
        let owner = profile.isPrivate ? profiles.profileToReturnTo : profile
        let context: BrowserProfileContext
        if browser.context.profile.id == profile.id {
            context = browser.context
        } else {
            context = .shared(for: profile, settingsOwner: owner)
        }
        if browser.context !== context {
            browser.context = context
            browser.adopt(database: context.database, sitePermissions: context.sitePermissions, privately: profile.isPrivate)
        }
        linkPeek.use(settings: context.settings)
        agentTurns.adopt(context: context)
        if profile.isPrivate {
            privateSession = PrivateBrowsingSession(database: context.database, dataStore: context.dataStore)
        } else {
            privateSession = nil
        }
        configureEngines()
        adoptSpaces(for: profile)
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
