// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit

/// Linen installs no SwiftUI `App` scene. SwiftUI replaces `NSApp.mainMenu`
/// during launch and discards the shortcuts set before it.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningTests else { return }
        NSApp.setActivationPolicy(.regular)
        guard MoveToApplications.offerIfNeeded() != .relaunching else { return }
        Task { await coordinator.bootstrap() }
        #if DEBUG
        AnimationProbe.runIfRequested(coordinator: coordinator)
        AnimationProbe.runSplitProbeIfRequested(coordinator: coordinator)
        StageRun.startIfRequested(coordinator: coordinator)
        #endif
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !isRunningTests else { return }
        coordinator.openFromAnotherApp(urls)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        coordinator.showBrowser()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard coordinator.settings.clearsDataOnQuit else { return .terminateNow }
        Task {
            await coordinator.clearDataOnQuitIfNeeded()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !isRunningTests else { return }
        coordinator.browser.saveBlocking()
        coordinator.conversationLog.saveBlocking()
    }
}
