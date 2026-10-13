// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum TestDefaults {
    // A path suite name keeps the plist out of ~/Library/Preferences.
    private static let folder: URL = {
        let folder = FileManager.default.temporaryDirectory.appending(path: "LinenTestDefaults", directoryHint: .isDirectory)
        sweep(folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    static func name(_ label: String) -> String {
        folder.appending(path: "\(label).\(UUID().uuidString)").path
    }

    static func suite(_ label: String) -> UserDefaults {
        UserDefaults(suiteName: name(label))!
    }

    private static func sweep(_ folder: URL) {
        let cutoff = Date(timeIntervalSinceNow: -600)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        for file in files {
            let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if let modified, modified < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
