// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Observation
import os
import Sparkle

@Observable
final class UpdateModel {
    enum Phase: Equatable {
        case idle
        case checking
        case available
        case upToDate
        case downloading
        case extracting
        case readyToInstall
        case installing
        case failed(String)
    }

    var phase: Phase = .idle
    var version = ""
    var progress: Double = 0
    var isProgressKnown = false
    var isDismissed = false
    var isShownInSettings = false

    var isBannerVisible: Bool {
        guard !isDismissed, !isShownInSettings else { return false }
        return switch phase {
        case .idle, .checking:
            false
        default:
            true
        }
    }
}

@MainActor
final class UpdateController: NSObject {
    let model = UpdateModel()

    private var updater: SPUUpdater?

    private var pendingChoice: ((SPUUserUpdateChoice) -> Void)?
    private var expectedBytes: UInt64 = 0
    private var receivedBytes: UInt64 = 0

    private var isUserInitiated = false
    private var transientTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func start() {
        let updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: self,
            delegate: self
        )
        updater.automaticallyChecksForUpdates = true
        updater.automaticallyDownloadsUpdates = false
        updater.updateCheckInterval = 60 * 60 * 4

        do {
            try updater.start()
            self.updater = updater
            Pipeline.log.notice("updater: started, feed \(UpdateFeed.appcastURL.absoluteString, privacy: .public)")
        } catch {
            Pipeline.log.error("updater: start failed - \(error, privacy: .public)")
        }
    }

    // MARK: - What the banner calls

    /// Sparkle refuses a check while a session already runs.
    var canCheck: Bool {
        updater?.canCheckForUpdates ?? false
    }

    func checkNow() {
        guard let updater, updater.canCheckForUpdates else { return }
        transientTask?.cancel()
        model.isDismissed = false
        updater.checkForUpdates()
    }

    func proceed() {
        let reply = pendingChoice
        pendingChoice = nil
        reply?(.install)
    }

    func dismiss() {
        model.isDismissed = true
        let reply = pendingChoice
        pendingChoice = nil
        reply?(.dismiss)
    }

    private func showTransiently(_ phase: UpdateModel.Phase) {
        model.isDismissed = false
        model.phase = phase
        transientTask?.cancel()
        transientTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, model.phase == phase else { return }
            model.phase = .idle
        }
    }

    private func resetTransfer() {
        expectedBytes = 0
        receivedBytes = 0
        model.progress = 0
        model.isProgressKnown = false
    }
}

// MARK: - Sparkle's flow, as state

extension UpdateController: SPUUserDriver {
    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        reply(SUUpdatePermissionResponse(
            automaticUpdateChecks: true,
            automaticUpdateDownloading: false,
            sendSystemProfile: false
        ))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        isUserInitiated = true
        model.phase = .checking
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        model.version = appcastItem.displayVersionString
        model.isDismissed = false
        pendingChoice = reply

        switch state.stage {
        case .notDownloaded:
            model.phase = .available
        case .downloaded, .installing:
            model.phase = .readyToInstall
        @unknown default:
            model.phase = .available
        }
        Pipeline.log.notice("updater: \(self.model.version, privacy: .public) available")
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        if isUserInitiated {
            showTransiently(.upToDate)
        } else {
            model.phase = .idle
        }
        acknowledgement()
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        Pipeline.log.error("updater: \(error, privacy: .public)")
        pendingChoice = nil
        if isUserInitiated {
            model.isDismissed = false
            model.phase = .failed(error.localizedDescription)
        } else {
            model.phase = .idle
        }
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        resetTransfer()
        model.phase = .downloading
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedBytes = expectedContentLength
        model.isProgressKnown = expectedContentLength > 0
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedBytes += length
        guard expectedBytes > 0 else { return }
        model.progress = min(1, Double(receivedBytes) / Double(expectedBytes))
    }

    func showDownloadDidStartExtractingUpdate() {
        model.progress = 0
        model.isProgressKnown = true
        model.phase = .extracting
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        model.progress = min(1, max(0, progress))
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        pendingChoice = reply
        model.isDismissed = false
        model.phase = .readyToInstall
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        model.phase = .installing
        if !applicationTerminated {
            retryTerminatingApplication()
        }
    }

    func showUpdateInstalledAndRelaunched(
        _ relaunched: Bool,
        acknowledgement: @escaping () -> Void
    ) {
        acknowledgement()
    }

    func showUpdateInFocus() {
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismissUpdateInstallation() {
        pendingChoice = nil
        isUserInitiated = false
        switch model.phase {
        case .installing, .upToDate, .failed:
            break
        default:
            model.phase = .idle
        }
        resetTransfer()
    }
}

// MARK: - Feed

extension UpdateController: SPUUpdaterDelegate {
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        UpdateFeed.appcastURL.absoluteString
    }
}
