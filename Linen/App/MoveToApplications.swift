// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import os

@MainActor
enum MoveToApplications {
    enum Outcome {
        case relaunching
        case staying
    }

    private static let declinedKey = "install.moveDeclined"
    private static let reregisterKey = "install.reregisterDefaultBrowser"

    static func offerIfNeeded(defaults: UserDefaults = .standard) -> Outcome {
        guard !isRunningTests else { return .staying }
        guard case let .offerMove(source, destination, isReadOnlySource) = decision(defaults: defaults) else {
            return .staying
        }
        guard ask(isReadOnlySource: isReadOnlySource) else {
            defaults.set(true, forKey: declinedKey)
            return .staying
        }
        return move(from: source, to: destination, isReadOnlySource: isReadOnlySource, defaults: defaults)
    }

    static func reregisterDefaultBrowserIfNeeded(defaults: UserDefaults = .standard) {
        guard defaults.bool(forKey: reregisterKey) else { return }
        defaults.set(false, forKey: reregisterKey)
        guard !DefaultBrowser.isCurrent else { return }
        Task { _ = await DefaultBrowser.request() }
    }

    // MARK: - The decision

    private static func decision(defaults: UserDefaults) -> InstallLocation.Decision {
        let manager = FileManager.default
        let bundle = Bundle.main.bundleURL
        let applications = manager.urls(for: .applicationDirectory, in: .allDomainsMask)
        let local = manager.urls(for: .applicationDirectory, in: .localDomainMask).first

        return InstallLocation.decide(
            bundle: bundle,
            originalBundle: Translocation.originalURL(of: bundle),
            applicationsDirectories: applications,
            destinationDirectory: local ?? URL(fileURLWithPath: "/Applications", isDirectory: true),
            isReadOnlySource: isOnReadOnlyVolume(bundle),
            hasDeclined: defaults.bool(forKey: declinedKey),
            isDebugBuild: isDebugBuild
        )
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static func isOnReadOnlyVolume(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
    }

    private static func ejectableVolume(of url: URL) -> URL? {
        guard let volume = (try? url.resourceValues(forKeys: [.volumeURLKey]))?.volume,
              volume.path.hasPrefix("/Volumes/")
        else { return nil }
        return volume
    }

    // MARK: - Asking

    private static func ask(isReadOnlySource: Bool) -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Move Linen to the Applications folder?")
        if isReadOnlySource {
            alert.informativeText = String(
                localized: "Software updates can fail when Linen runs from another folder. Linen will copy itself to Applications and reopen."
            )
        } else {
            alert.informativeText = String(
                localized: "Software updates can fail when Linen runs from another folder. Linen will move itself to Applications and reopen."
            )
        }
        alert.addButton(withTitle: String(localized: "Move to Applications"))
        alert.addButton(withTitle: String(localized: "Not Now"))
        alert.buttons.last?.keyEquivalent = "\u{1b}"

        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - Moving

    private static func move(
        from source: URL,
        to destination: URL,
        isReadOnlySource: Bool,
        defaults: UserDefaults
    ) -> Outcome {
        if let running = runningCopy(at: destination) {
            running.activate()
            quit()
        }

        do {
            try install(from: source, to: destination)
        } catch {
            Pipeline.log.error("install: copy failed: \(error, privacy: .public)")
            guard escalatedInstall(from: source, to: destination) else {
                NSWorkspace.shared.activateFileViewerSelecting([source])
                return .staying
            }
        }

        stripQuarantine(at: destination)
        if DefaultBrowser.isCurrent {
            defaults.set(true, forKey: reregisterKey)
        }
        if !isReadOnlySource {
            try? FileManager.default.removeItem(at: source)
        }

        relaunch(at: destination, ejecting: isReadOnlySource ? ejectableVolume(of: source) : nil)
        return .relaunching
    }

    private static func runningCopy(at destination: URL) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { application in
            application.bundleURL?.resolvingSymlinksInPath() == destination.resolvingSymlinksInPath()
        }
    }

    private static func install(from source: URL, to destination: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: destination.path) {
            try manager.trashItem(at: destination, resultingItemURL: nil)
        }
        do {
            try manager.copyItem(at: source, to: destination)
        } catch {
            try? manager.removeItem(at: destination)
            throw error
        }
    }

    /// `/Applications` belongs to the admin group, so a standard account cannot
    /// write to it. This raises the system authorisation panel.
    private static func escalatedInstall(from source: URL, to destination: URL) -> Bool {
        let command = "/bin/rm -rf \(shellQuoted(destination.path))"
            + " && /usr/bin/ditto \(shellQuoted(source.path)) \(shellQuoted(destination.path))"
        let script = "do shell script \"\(appleScriptQuoted(command))\" with administrator privileges"

        var failure: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&failure)
        if let failure {
            Pipeline.log.error("install: privileged copy failed: \(String(describing: failure), privacy: .public)")
            return false
        }
        return FileManager.default.fileExists(atPath: destination.path)
    }

    private static func stripQuarantine(at url: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        task.arguments = ["-d", "-r", "com.apple.quarantine", url.path]
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            Pipeline.log.error("install: clearing quarantine failed: \(error, privacy: .public)")
        }
    }

    private static func relaunch(at destination: URL, ejecting volume: URL?) {
        var script = "while /bin/kill -0 \(getpid()) 2>/dev/null; do /bin/sleep 0.1; done"
        if let volume {
            script += "; /usr/bin/hdiutil detach \(shellQuoted(volume.path)) -quiet || true"
        }
        script += "; /usr/bin/open \(shellQuoted(destination.path))"

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script]
        do {
            try task.run()
        } catch {
            Pipeline.log.error("install: relaunch failed: \(error, privacy: .public)")
        }
        quit()
    }

    /// `NSApp.terminate` runs the save handlers, which would write an empty
    /// session over the real one: nothing has been restored at this point.
    private static func quit() -> Never {
        exit(0)
    }

    private static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptQuoted(_ command: String) -> String {
        command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

/// Gatekeeper runs a quarantined app from a read-only mount until the user
/// moves it in the Finder. The framework reports the real path, but only
/// through symbols that ship without a header.
private enum Translocation {
    private typealias IsTranslocated =
        @convention(c) (CFURL, UnsafeMutablePointer<Bool>, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool
    private typealias OriginalPath =
        @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?

    static func originalURL(of url: URL) -> URL? {
        let security = "/System/Library/Frameworks/Security.framework/Security"
        guard let library = dlopen(security, RTLD_LAZY),
              let check = dlsym(library, "SecTranslocateIsTranslocatedURL"),
              let original = dlsym(library, "SecTranslocateCreateOriginalPathForURL")
        else { return nil }

        var isTranslocated = false
        let answered = unsafeBitCast(check, to: IsTranslocated.self)(url as CFURL, &isTranslocated, nil)
        guard answered, isTranslocated else { return nil }

        return unsafeBitCast(original, to: OriginalPath.self)(url as CFURL, nil)?.takeRetainedValue() as URL?
    }
}
