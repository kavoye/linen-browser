// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Testing

@testable import Linen

struct PeekExitTests {
    private let frame = CGRect(x: 0, y: 0, width: 280, height: 800)

    @Test func aPointerOnThePeekKeepsItOpen() {
        #expect(!PeekExit.hasLeft(pointer: CGPoint(x: 4, y: 400), frame: frame))
    }

    @Test func aPointerThatNeverEnteredStillEndsThePeek() {
        #expect(PeekExit.hasLeft(pointer: CGPoint(x: -40, y: 400), frame: frame))
        #expect(PeekExit.hasLeft(pointer: CGPoint(x: 120, y: -10), frame: frame))
    }

    @Test func anUnmeasuredPeekWaitsForItsFrame() {
        #expect(!PeekExit.hasLeft(pointer: CGPoint(x: 600, y: 400), frame: .zero))
    }

    @Test func theResizeEdgeKeepsAPeekOpen() {
        let edge = CGPoint(x: frame.maxX + 7, y: 400)
        #expect(!PeekExit.hasLeft(pointer: edge, frame: frame, trailingReach: PeekExit.resizeReach))
        #expect(PeekExit.hasLeft(pointer: edge, frame: frame))
    }

    @Test func pastTheResizeEdgeThePeekEnds() {
        let past = CGPoint(x: frame.maxX + PeekExit.resizeReach + 1, y: 400)
        #expect(PeekExit.hasLeft(pointer: past, frame: frame, trailingReach: PeekExit.resizeReach))
    }

    @Test func aPeekWithoutAWindowEnds() {
        #expect(PeekExit.hasLeft(pointer: nil, frame: frame))
    }
}

struct PeekEdgeTests {
    private let strip = CGRect(x: 0, y: 0, width: PeekEdge.width, height: 800)

    @Test func aPointerRestingOnTheEdgeOpensThePeek() {
        #expect(PeekEdge.isHeld(pointer: CGPoint(x: 3, y: 400), frame: strip))
    }

    @Test func aPointerThatCrossedTheEdgeOpensNothing() {
        #expect(!PeekEdge.isHeld(pointer: CGPoint(x: -30, y: 400), frame: strip))
        #expect(!PeekEdge.isHeld(pointer: CGPoint(x: 40, y: 400), frame: strip))
    }

    @Test func anUnknownPointerOrStripOpensNothing() {
        #expect(!PeekEdge.isHeld(pointer: nil, frame: strip))
        #expect(!PeekEdge.isHeld(pointer: CGPoint(x: 3, y: 400), frame: .zero))
    }
}

@MainActor
struct PeekWatchTests {
    private let center = NotificationCenter()
    private let window = NSWindow()

    @Test func leavingTheAppChecksThePointer() {
        let watch = PeekWatch(center: center)
        var checks = 0
        watch.start(window: window) { checks += 1 }
        center.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        #expect(checks == 1)
        watch.stop()
    }

    @Test func leavingTheWindowChecksThePointer() {
        let watch = PeekWatch(center: center)
        var checks = 0
        watch.start(window: window) { checks += 1 }
        center.post(name: NSWindow.didResignKeyNotification, object: window)
        center.post(name: NSWindow.didResignKeyNotification, object: NSWindow())
        #expect(checks == 1)
        watch.stop()
    }

    @Test func aStoppedWatchChecksNothing() {
        let watch = PeekWatch(center: center)
        var checks = 0
        watch.start(window: window) { checks += 1 }
        watch.stop()
        center.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        center.post(name: NSWindow.didResignKeyNotification, object: window)
        #expect(checks == 0)
    }

    @Test func restartingReplacesTheOldWatch() {
        let watch = PeekWatch(center: center)
        var checks = 0
        watch.start(window: window) { checks += 1 }
        watch.start(window: window) { checks += 1 }
        center.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        #expect(checks == 1)
        watch.stop()
    }
}
