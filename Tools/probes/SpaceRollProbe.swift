// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import os
import QuartzCore

@MainActor
final class SpaceRollProbe: NSObject {
    enum Phase: String {
        case swipe
        case finish
    }

    static let shared = SpaceRollProbe()

    #if DEBUG
    private var link: CADisplayLink?
    private var start: CFTimeInterval = 0
    private var last: CFTimeInterval = 0
    private var slow: [String] = []
    private var phase = Phase.finish

    func mark(_ note: String) {
        guard link != nil else { return }
        slow.append(String(format: "[%@ at +%.0fms]", note, (CACurrentMediaTime() - start) * 1000))
    }

    func begin(_ phase: Phase, in view: NSView?) {
        if phase == .finish, self.phase == .swipe, link != nil {
            mark("release")
            return
        }
        link?.invalidate()
        guard let view else { return }
        start = CACurrentMediaTime()
        last = start
        slow = []
        self.phase = phase
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let gap = (now - last) * 1000
        if gap > 12 {
            slow.append(String(format: "%.0fms at +%.0fms", gap, (last - start) * 1000))
        }
        last = now
        guard now - start > (phase == .swipe ? 1.1 : 0.7) else { return }
        link.invalidate()
        self.link = nil
        let summary = slow.isEmpty ? "none" : slow.joined(separator: ", ")
        Pipeline.log.notice("space \(self.phase.rawValue, privacy: .public): slow frames \(summary, privacy: .public)")
    }
    #else
    func mark(_ note: String) {}

    func begin(_ phase: Phase, in view: NSView?) {}
    #endif
}
