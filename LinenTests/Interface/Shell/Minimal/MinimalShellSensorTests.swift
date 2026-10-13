// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Testing

@testable import Linen

@MainActor
struct MinimalShellSensorTests {
    private typealias Travel = MinimalShellSensor.ScrollTravel

    @Test func aSmallScrollMovesNothing() {
        var travel = Travel()

        #expect(travel.add(6, beginsGesture: true) == nil)
        #expect(travel.add(6, beginsGesture: false) == nil)
    }

    @Test func scrollingPastTheThresholdReportsItsDirectionOnce() {
        var travel = Travel()

        #expect(travel.add(10, beginsGesture: true) == nil)
        #expect(travel.add(10, beginsGesture: false) == true)
        #expect(travel.add(10, beginsGesture: false) == nil, "the distance starts again after a report")

        var down = Travel()
        #expect(down.add(-20, beginsGesture: true) == false)
    }

    @Test func turningBackStartsTheDistanceAgain() {
        var travel = Travel()

        #expect(travel.add(12, beginsGesture: true) == nil)
        #expect(travel.add(-12, beginsGesture: false) == nil, "12 up and 12 down do not add up")
        #expect(travel.add(-4, beginsGesture: false) == false)
    }

    @Test func aNewGestureForgetsTheLastOne() {
        var travel = Travel()

        #expect(travel.add(12, beginsGesture: true) == nil)
        #expect(travel.add(12, beginsGesture: true) == nil)
    }

    private func window(with sensor: MinimalShellSensor.SensorView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        sensor.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        window.contentView?.addSubview(sensor)
        return window
    }

    private func controlsHidden(in window: NSWindow) -> [Bool] {
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0)?.isHidden }
    }

    @Test func theSensorHidesTheWindowControlsUntilTheyArePinned() {
        let sensor = MinimalShellSensor.SensorView()
        let window = window(with: sensor)
        defer {
            sensor.removeFromSuperview()
            window.close()
        }

        #expect(controlsHidden(in: window) == [true, true, true])

        sensor.pinsWindowControls = true
        #expect(controlsHidden(in: window) == [false, false, false])

        sensor.pinsWindowControls = false
        #expect(controlsHidden(in: window) == [true, true, true])
    }

    @Test func leavingTheWindowGivesTheControlsBack() {
        let sensor = MinimalShellSensor.SensorView()
        let window = window(with: sensor)
        defer { window.close() }

        sensor.removeFromSuperview()

        #expect(controlsHidden(in: window) == [false, false, false])
    }
}
