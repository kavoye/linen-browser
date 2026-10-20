// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Testing

@testable import Linen

@MainActor
@Suite(
    .serialized,
    .boundedWebViews,
    .enabled(if: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
)
struct WindowBloomTests {
    private func autosaveName(for coordinator: AppCoordinator) -> String {
        "linen.browser.window.\(coordinator.windowID.uuidString)"
    }

    private func forget(_ coordinator: AppCoordinator) {
        coordinator.closeWindow()
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame " + autosaveName(for: coordinator))
    }

    private func withoutSavedFrame(_ body: () throws -> Void) rethrows {
        let key = "NSWindow Frame linen.browser.window.\(BrowserModel.legacyWindowID.uuidString)"
        let saved = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        try body()
    }

    private func openingFrame() throws -> NSRect {
        let reference = AppCoordinator()
        defer { forget(reference) }
        reference.showBrowser(activate: false)
        return try #require(reference.nativeWindow).frame
    }

    private func close(_ a: CGFloat, _ b: CGFloat) -> Bool {
        abs(a - b) <= 1
    }

    @Test func onboardingOpensASmallerCentredWindowThatSavesNoFrame() throws {
        try withoutSavedFrame {
            let opening = try openingFrame()
            let coordinator = AppCoordinator()
            defer { forget(coordinator) }

            coordinator.prepareWindowBloom()

            let window = try #require(coordinator.nativeWindow)
            #expect(close(window.frame.width, opening.width * 0.8))
            #expect(close(window.frame.height, opening.height * 0.8))
            #expect(close(window.frame.midX, opening.midX))
            #expect(close(window.frame.midY, opening.midY))
            #expect(window.frameAutosaveName.isEmpty, "a frame saved now would reopen the window small")
        }
    }

    @Test func theWindowSavesNoFrameWhileItGrows() throws {
        try withoutSavedFrame {
            let opening = try openingFrame()
            let coordinator = AppCoordinator()
            defer { forget(coordinator) }
            coordinator.prepareWindowBloom()
            let window = try #require(coordinator.nativeWindow)

            coordinator.growWindowAfterOnboarding()

            #expect(window.frameAutosaveName.isEmpty, "a frame saved mid-animation would reopen the window small")
            let frozen = try #require(coordinator.frozenShellSize, "the shell keeps its final size while the window grows")
            let final = window.contentRect(forFrameRect: opening).size
            #expect(close(frozen.width, final.width))
            #expect(close(frozen.height, final.height))
        }
    }

    @Test func growingWithoutABloomChangesNothing() throws {
        try withoutSavedFrame {
            let coordinator = AppCoordinator()
            defer { forget(coordinator) }
            coordinator.showBrowser(activate: false)
            let window = try #require(coordinator.nativeWindow)
            let before = window.frame

            coordinator.growWindowAfterOnboarding()

            #expect(window.frame == before)
        }
    }
}
