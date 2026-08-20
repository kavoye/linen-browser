// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum InstallLocation {
    enum Decision: Equatable {
        case installed
        case offerMove(from: URL, to: URL, isReadOnlySource: Bool)
        case skip
    }

    static func decide(
        bundle: URL,
        originalBundle: URL?,
        applicationsDirectories: [URL],
        destinationDirectory: URL,
        isReadOnlySource: Bool,
        hasDeclined: Bool,
        isDebugBuild: Bool
    ) -> Decision {
        guard !isDebugBuild else { return .skip }

        let source = originalBundle ?? bundle
        guard !isInstalled(source, in: applicationsDirectories) else { return .installed }
        guard !hasDeclined else { return .skip }

        let destination = destinationDirectory.appending(path: source.lastPathComponent)
        return .offerMove(from: source, to: destination, isReadOnlySource: isReadOnlySource)
    }

    static func isInstalled(_ bundle: URL, in directories: [URL]) -> Bool {
        let path = resolved(bundle)
        return directories.contains { directory in
            let root = resolved(directory)
            return path == root || path.hasPrefix(root + "/")
        }
    }

    private static func resolved(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
