// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

@MainActor
final class PageZoomStore {
    static private(set) var shared = PageZoomStore()

    static func use(file: URL) {
        shared = PageZoomStore(file: file)
    }

    private var levels: [String: Double]
    private let file: URL

    init(file: URL = PageZoomStore.defaultFile) {
        self.file = file
        levels = (try? Data(contentsOf: file))
            .flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) } ?? [:]
    }

    func level(for host: String) -> CGFloat? {
        levels[host].map { CGFloat($0) }
    }

    func set(_ zoom: CGFloat, for host: String, defaultZoom: CGFloat = BrowserSettings.shared.pageZoom) {
        guard !host.isEmpty else { return }
        if abs(zoom - defaultZoom) < 0.005 {
            guard levels.removeValue(forKey: host) != nil else { return }
        } else {
            let value = Double(zoom)
            guard levels[host] != value else { return }
            levels[host] = value
        }
        let snapshot = levels
        Task { await JSONFileStore.shared.write(snapshot, to: file) }
    }

    private static var defaultFile: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Linen", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("page-zoom.json")
    }
}
