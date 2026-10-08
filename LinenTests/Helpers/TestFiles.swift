// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum TestFiles {
    static let directory: URL = {
        let temporary = FileManager.default.temporaryDirectory
        let root = temporary.appending(path: "LinenTestFiles", directoryHint: .isDirectory)
        sweep(root)
        sweep(temporary) { $0.hasPrefix("Linen-tests-") }
        let run = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
        atexit { try? FileManager.default.removeItem(at: TestFiles.directory) }
        return run
    }()

    private static func sweep(_ root: URL, matching include: (String) -> Bool = { _ in true }) {
        let cutoff = Date(timeIntervalSinceNow: -600)
        let runs = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        for run in runs where include(run.lastPathComponent) {
            let modified = try? run.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if let modified, modified < cutoff {
                try? FileManager.default.removeItem(at: run)
            }
        }
    }
}
