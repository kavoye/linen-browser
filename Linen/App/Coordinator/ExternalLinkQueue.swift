// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct ExternalLinkQueue {
    private var queued: [URL] = []
    private var isReady = false

    mutating func accept(_ urls: [URL]) -> [URL]? {
        let web = urls.filter { $0.scheme == "http" || $0.scheme == "https" || $0.isFileURL }
        guard !web.isEmpty else { return nil }
        guard isReady else {
            queued.append(contentsOf: web)
            return nil
        }
        return web
    }

    mutating func open() -> [URL] {
        isReady = true
        defer { queued = [] }
        return queued
    }
}
