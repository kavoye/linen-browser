// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct TabScrollReturn {
    private(set) var lastY: Double = 0
    private var lastURL: URL?
    private var memory = ScrollReturnMemory()

    mutating func report(_ y: Double, at url: URL?) {
        lastY = y
        lastURL = url
    }

    mutating func forget() {
        lastY = 0
        lastURL = nil
    }

    mutating func remember() {
        memory.remember(lastY, leaving: lastURL?.absoluteString)
    }

    mutating func offset(returningTo url: URL?) -> Double? {
        guard let stored = memory.offset(returningTo: url?.absoluteString) else { return nil }
        report(stored, at: url)
        return stored
    }
}
