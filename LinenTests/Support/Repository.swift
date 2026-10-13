// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The repository checkout, found by walking up from this file until the
/// project file appears, so moving the test does not break the lookup.
enum Repository {
    nonisolated static let root: URL = {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            let project = directory.appending(path: "Linen.xcodeproj").path
            if FileManager.default.fileExists(atPath: project) {
                return directory
            }
            directory = directory.deletingLastPathComponent()
        }
        return directory
    }()
}
