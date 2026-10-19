// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import os
import WebKit

extension AppCoordinator {
    // MARK: - Launch

    func prepareBrowser(restoring: Bool, show: Bool = true, urls: [URL] = []) {
        guard !isBootstrapped else { return }
        isBootstrapped = true
        var timing = BootstrapTiming()
        Pipeline.log.notice("bootstrap: begin")
        OutputDucker.restoreAfterUncleanExit()
        applyProfileStores(profiles.current)
        followSettings()
        timing.mark("profile and assistant")
        memoryPressure.onPressure = { [weak self] level in
            self?.relieveMemoryPressure(level)
        }
        memoryPressure.start()
        if application == nil {
            let menu = MainMenu(coordinator: self)
            menu.install()
            mainMenu = menu
        }
        prepareWindowWebServices()
        timing.mark("web setup")
        if restoring {
            browser.restoreSession()
        }
        for url in urls.reversed() {
            browser.newTab(url: url, transition: .link)
        }
        browser.ensureActiveTab()
        retainAgentMemory()
        archiveSweeper.onSweep = { [weak self] in
            self?.browser.archiveStaleTabs()
            self?.sleepIdleTabs()
        }
        archiveSweeper.start()
        timing.mark("session")
        wireMedia()
        linkPeek.begin()
        if application == nil || application?.windows.count == 1 {
            onboarding.beginIfNeeded()
        }
        if onboarding.isPresented {
            prepareWindowBloom()
        }
        timing.mark("window preparation")
        showBrowser(activate: show)
        timing.mark("show window")
        if application == nil {
            mcpServer.makeToolkit = { [weak self] browser in
                guard let self, self.browser === browser else { return nil }
                return makeExternalToolkit()
            }
            mcpServer.resume()
        }
        if !AppDatabase.ownsSession {
            self.notice.show(String(localized: "Another copy of Linen is running. Changes in this window won’t be saved."))
        }
        drainQueuedExternalURLs()
        timing.mark("post-window setup")

        if application == nil || application?.windows.count == 1 {
            startUpdates()
        }
        MoveToApplications.reregisterDefaultBrowserIfNeeded()
        timing.mark("updates")
        Task { [weak self] in
            guard let self, application == nil || application?.windows.count == 1,
                  await releaseNotes.shouldOpenForNewVersion() else { return }
            guard !isClosed else { return }
            showReleaseNotes()
        }

        Task { [extensions] in
            await extensions.start()
            await extensions.updateInstalledIfDue()
        }

        activation.onPress = { [weak self] in
            guard let self, isKeyWindow, !onboarding.isPresented, microphoneIsReady() else { return }
            voiceInput.begin()
        }
        activation.onRelease = { [weak self] in
            guard let self, !onboarding.isPresented else { return }
            voiceInput.scheduleFinish()
        }
        activation.setSuspended(!isKeyWindow)
        activation.start()
        installKeyMonitors()
        installDownloadFlights()

        timing.mark("services")
        timing.log()
    }

    func prepareWindowWebServices() {
        browser.context.contentBlocker.refresh()
        if let application {
            application.prepareWebScripts(for: self)
        } else {
            browser.context.webViewPool.prepare(
                scriptSource: MediaCenter.frameScriptSource,
                handlerName: MediaCenter.frameScriptHandlerName,
                handler: media.frameScriptHandler
            )
        }
        browser.context.webViewPool.addScript(
            GeolocationBridge.scriptSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            handlerName: GeolocationBridge.handlerName,
            handler: GeolocationBridge.shared
        )
        browser.context.webViewPool.addScript(
            NotificationBridge.scriptSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            handlerName: NotificationBridge.handlerName,
            handler: NotificationBridge.shared
        )
        if application == nil {
            GeolocationBridge.shared.tabResolver = { [weak self] webView in
                self?.browser.tabs.first { $0.isMaterialised && $0.webView === webView }
            }
            NotificationBridge.shared.tabResolver = GeolocationBridge.shared.tabResolver
        }
        browser.context.webViewPool.installExtensionController(extensions.controller)
    }

    private func startUpdates() {
        updates.setChannel(settings.updateChannel)
        settings.onUpdateChannelChanged = { [weak self] channel in
            self?.updates.setChannel(channel)
        }
        updates.start()
    }

    private func installDownloadFlights() {
        downloadFlights.watchClicks { [weak self] in self?.nativeWindow }
        browser.downloads.apply(settings.downloadRetention)
    }
}

private struct BootstrapTiming {
    private let start = ContinuousClock.now
    private var last: ContinuousClock.Instant?
    private var phases: [String] = []

    mutating func mark(_ phase: String) {
        let now = ContinuousClock.now
        phases.append("\(phase) \((now - (last ?? start)).milliseconds)ms")
        last = now
    }

    func log() {
        let total = (ContinuousClock.now - start).milliseconds
        let detail = phases.joined(separator: ", ")
        Pipeline.log.notice("bootstrap: done in \(total, privacy: .public)ms, \(detail, privacy: .public)")
    }
}
