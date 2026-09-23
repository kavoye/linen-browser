// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct BrowserVisualWorkflowTests {
    @Test func visualToolsClickAndReturnANewScreenshot() async throws {
        let fixture = try await ComputerWorkflowFixture()
        defer { fixture.close() }
        fixture.toolkit.beginTask(.init(id: UUID(), tabID: fixture.tab.id))

        let screenshot = await fixture.toolkit.screenshotPage()
        #expect(screenshot.contains("Screenshot captured."))
        #expect(fixture.toolkit.takePendingScreenshot() != nil)
        let frame = try #require(fixture.toolkit.computerObservation)
        let x = Int(60 * frame.pixels.width / frame.geometry.width)
        let y = Int(110 * frame.pixels.height / frame.geometry.height)
        let result = await fixture.toolkit.visualAction(name: "clickAtPoint", action: [
            "type": "click", "button": "left", "x": .integer(Int64(x)), "y": .integer(Int64(y)),
        ])

        #expect(result.contains("CONTROL: Browser action completed."))
        #expect(try await fixture.tab.webView.evaluateJavaScript("window.chosen || 0") as? Int == 1)
        #expect(fixture.toolkit.takePendingScreenshot() != nil)
        #expect(fixture.tab.webView.subviews.contains { $0.identifier?.rawValue == "assistant-pointer" })
    }
}
