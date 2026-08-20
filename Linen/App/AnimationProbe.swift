// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

#if DEBUG
import AppKit
import SwiftUI

@MainActor
enum AnimationProbe {
    static func runSplitProbeIfRequested(coordinator: AppCoordinator) {
        guard ProcessInfo.processInfo.environment["LINEN_SPLIT_PROBE"] == "1" else { return }
        let dir = URL(fileURLWithPath: "/tmp/linen-split-probe", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        Task {
            try? await Task.sleep(for: .seconds(2.5))
            let browser = coordinator.browser
            let topLeft = browser.newTab(url: URL(string: "https://example.com"))
            let topRight = browser.newTab(url: URL(string: "https://www.wikipedia.org"))
            let bottomLeft = browser.newTab(url: URL(string: "https://example.org"))
            let bottomRight = browser.newTab(url: URL(string: "https://www.wikipedia.org/wiki/Cat"))
            try? await Task.sleep(for: .seconds(5))

            browser.split(topLeft, with: topRight, axis: .sideBySide)
            browser.activate(topRight)
            try? await Task.sleep(for: .seconds(3))
            capture(to: dir.appendingPathComponent("two.png"))

            browser.insertIntoSplit(bottomLeft, beside: topLeft, edge: .bottom)
            try? await Task.sleep(for: .seconds(3))
            capture(to: dir.appendingPathComponent("three.png"))

            browser.insertIntoSplit(bottomRight, beside: bottomLeft, edge: .right)
            try? await Task.sleep(for: .seconds(3.5))
            capture(to: dir.appendingPathComponent("four.png"))

            if let grid = browser.activeSplit {
                let layout = SplitLayout(
                    grid: grid,
                    size: coordinator.sidebarDrag.contentFrameInWindow.size,
                    gutter: SplitMetrics.gutter
                )
                if let seam = layout.seams.first(where: { $0.axis == .stacked }) {
                    browser.setSplitSeam(seam, containing: topLeft, leading: 0.65, minimum: 0.15)
                }
            }
            try? await Task.sleep(for: .seconds(1.5))
            capture(to: dir.appendingPathComponent("four-65.png"))

            browser.dissolveSplit(containing: topLeft)
            browser.split(topLeft, with: topRight, axis: .sideBySide)
            browser.insertIntoSplit(bottomLeft, beside: topRight, edge: .right)
            browser.insertIntoSplit(bottomRight, beside: bottomLeft, edge: .right)
            browser.activate(topLeft)
            try? await Task.sleep(for: .seconds(3))
            capture(to: dir.appendingPathComponent("four-in-a-row.png"))

            browser.dissolveSplit(containing: topLeft)
            browser.split(topLeft, with: topRight, axis: .sideBySide)
            browser.insertIntoSplit(bottomLeft, beside: topRight, edge: .bottom)
            browser.insertIntoSplit(bottomRight, beside: bottomLeft, edge: .bottom)
            browser.activate(topLeft)
            try? await Task.sleep(for: .seconds(3))
            capture(to: dir.appendingPathComponent("one-beside-three.png"))

            browser.dissolveSplit(containing: topLeft)
            browser.split(topLeft, with: topRight, axis: .sideBySide)
            browser.insertIntoSplit(bottomLeft, beside: topLeft, edge: .bottom)
            browser.insertIntoSplit(bottomRight, beside: bottomLeft, edge: .right)
            browser.activate(topRight)
            try? await Task.sleep(for: .seconds(3))

            browser.removeFromSplit(bottomRight)
            try? await Task.sleep(for: .seconds(2))
            capture(to: dir.appendingPathComponent("back-to-three.png"))

            let drop = coordinator.sidebarDrag
            drop.source = .row
            drop.target = drop.dropPlan.targets.first {
                $0.anchor == topLeft.id && $0.displaces
            }
            try? await Task.sleep(for: .seconds(1.5))
            capture(to: dir.appendingPathComponent("aim-left-of-full-row.png"))

            drop.target = drop.dropPlan.targets.first {
                $0.anchor == topRight.id && $0.displaces
            }
            try? await Task.sleep(for: .seconds(1.5))
            capture(to: dir.appendingPathComponent("aim-below-a-full-grid.png"))

            browser.removeFromSplit(bottomLeft)
            try? await Task.sleep(for: .seconds(0.5))
            drop.target = drop.dropPlan.targets.first { !$0.displaces }
            try? await Task.sleep(for: .seconds(1.5))
            capture(to: dir.appendingPathComponent("aim-new-row.png"))

            drop.clearDrop()

            try? Data().write(to: dir.appendingPathComponent("done"))
        }
    }

    static func runIfRequested(coordinator: AppCoordinator) {
        guard ProcessInfo.processInfo.environment["LINEN_ANIM_PROBE"] == "1" else { return }
        let dir = URL(fileURLWithPath: "/tmp/linen-anim-probe", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        Task {
            try? await Task.sleep(for: .seconds(2.5))
            await probe(into: dir, label: "open") { coordinator.openNewTab() }
            try? await Task.sleep(for: .seconds(1))
            await probe(into: dir, label: "open2") { coordinator.openNewTab() }
            try? await Task.sleep(for: .seconds(1))
            await probe(into: dir, label: "close") { coordinator.browser.closeActiveTab() }
            try? await Task.sleep(for: .seconds(1))
            await probe(into: dir, label: "close2") { coordinator.browser.closeActiveTab() }
            try? Data().write(to: dir.appendingPathComponent("done"))
        }
    }

    private static func probe(into dir: URL, label: String, mutate: () -> Void) async {
        capture(to: dir.appendingPathComponent("\(label)-before.png"))
        mutate()
        for i in 0..<16 {
            capture(to: dir.appendingPathComponent("\(label)-\(String(format: "%02d", i)).png"))
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    private static func capture(to url: URL) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 400 }),
              let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
