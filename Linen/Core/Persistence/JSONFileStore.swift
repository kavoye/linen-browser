// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

actor JSONFileStore {
    static let shared = JSONFileStore()

    func write(_ value: some Encodable & Sendable, to url: URL, sortedKeys: Bool = false) {
        Self.encodeAndWrite(value, to: url, sortedKeys: sortedKeys)
    }

    nonisolated static func encodeAndWrite(
        _ value: some Encodable,
        to url: URL,
        sortedKeys: Bool = false
    ) {
        let encoder = JSONEncoder()

        if sortedKeys {
            encoder.outputFormatting = [.sortedKeys]

        }

        guard let data = try? encoder.encode(value) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }
}
