// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension AppCoordinator {
    func followSettings() {
        let profileID = browser.context.profile.id
        github.announce = { update in
            NotificationBridge.shared.post(
                title: update.pr.title, subtitle: "\(update.pr.repository.nameWithOwner) #\(update.pr.number)",
                body: update.summary, identifier: "github-\(update.pr.id)", link: update.pr.url,
                profileID: profileID
            )
        }
        NotificationBridge.shared.linkOpener = { [weak application] url, profileID in
            guard let application, let profileID,
                  let profile = ProfileStore.shared.profiles.first(where: { $0.id == profileID }) else { return }
            let windows = application.windows.filter { $0.profiles.current.id == profileID }
            let window = windows.first { $0.isKeyWindow } ?? windows.last ?? application.newWindow(profile: profile)
            window.showBrowser()
            window.openGitHubLink(url)
        }
        if !AppDatabase.isRunningTests, settings.showsGitHub {
            github.start()
        }
        let context = browser.context
        let targets: () -> [AppCoordinator] = { [weak context, weak application, weak self] in
            guard let context else { return [] }
            return application?.windows.filter { $0.browser.context === context }
                ?? self.map { [$0] } ?? []
        }
        settings.onWebPreferencesChanged = {
            targets().forEach { $0.browser.applyWebSettings() }
        }
        settings.onAppearanceChanged = {
            targets().forEach { $0.updateWindowAppearance() }
        }
        settings.onMediaPlayerChanged = { isOn in
            targets().forEach { $0.media.isEnabled = isOn }
        }
        settings.onAutomaticPictureInPictureChanged = { _ in
            targets().forEach { $0.applyPictureLending() }
        }
        settings.onVideoInPlayerChanged = { _ in
            targets().forEach { $0.applyPictureLending() }
        }
        settings.onLyricsChanged = { isOn in
            targets().forEach { $0.sidePanel.setAvailable(isOn, for: .lyrics) }
        }
        settings.onArchiveTabsAfterChanged = { _ in
            targets().forEach { $0.browser.archiveStaleTabs() }
        }
        settings.onGitHubChanged = { [weak context] isOn in
            targets().forEach { $0.sidePanel.setAvailable(isOn, for: .github) }
            guard !AppDatabase.isRunningTests, let github = context?.github else { return }
            if isOn {
                github.start()
            } else {
                github.stop()
            }
        }
        media.isEnabled = settings.showsMediaPlayer
        applyPictureLending()
        sidePanel.setAvailable(settings.showsLyrics, for: .lyrics)
        sidePanel.setAvailable(settings.showsGitHub, for: .github)
        context.pageWatches.onAvailabilityChange = { hasWatches in
            targets().forEach { $0.sidePanel.setAvailable(hasWatches, for: .watches) }
        }
        sidePanel.setAvailable(!context.pageWatches.watches.isEmpty, for: .watches)
        updateWindowAppearance()
        browser.downloads.webViewProvider = {
            let windows = targets()
            return (windows.first { $0.isKeyWindow } ?? windows.last)?.browser.activeTab?.webView
        }
        browser.downloads.onFinished = { filename in
            let windows = targets()
            (windows.first { $0.isKeyWindow } ?? windows.last)?
                .notice.show(String(localized: "Downloaded \(filename)"), symbol: "arrow.down.circle")
        }
        browser.downloads.onStarted = { filename in
            let windows = targets()
            (windows.first { $0.isKeyWindow } ?? windows.last)?
                .notice.show(String(localized: "notice.downloadStarted", defaultValue: "Downloading \(filename)"), symbol: "arrow.down.circle")
        }
        browser.downloads.onFailed = { filename in
            let windows = targets()
            (windows.first { $0.isKeyWindow } ?? windows.last)?
                .notice.show(String(localized: "Couldn’t download \(filename)"), symbol: "arrow.down.circle", isWarning: true)
        }
        browser.downloads.onBegin = {
            targets().first { $0.isKeyWindow }?.downloadFlights.launch()
        }
    }
}
