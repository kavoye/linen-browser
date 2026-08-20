// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Testing

@testable import Linen

@MainActor
struct HoldToTalkMonitorTests {
    private static let optionKeyCode: UInt16 = 58
    private static let spaceKeyCode: UInt16 = 49
    private static let otherKeyCode: UInt16 = 40

    private static let combination = ActivationShortcut(
        keyCode: spaceKeyCode, modifiers: [.option], label: "Space"
    )

    private static let modifierOnly = ActivationShortcut(keyCode: optionKeyCode, label: "⌥")

    private final class Log {
        var presses = 0
        var releases = 0
    }

    private func monitor(_ shortcut: ActivationShortcut) -> (HoldToTalkMonitor, Log) {
        let log = Log()
        let subject = HoldToTalkMonitor(talk: { shortcut })
        subject.onPress = { log.presses += 1 }
        subject.onRelease = { log.releases += 1 }
        return (subject, log)
    }

    private func key(
        _ type: NSEvent.EventType,
        _ keyCode: UInt16,
        _ flags: NSEvent.ModifierFlags = [],
        isARepeat: Bool = false
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: isARepeat,
            keyCode: keyCode
        )!
    }

    // MARK: - A key shortcut

    @Test func holdingTheShortcutPressesOnceAndReleasesOnce() {
        let (subject, log) = monitor(Self.combination)

        #expect(subject.handle(key(.keyDown, Self.spaceKeyCode, [.option])) == .consumed)
        #expect(log.presses == 1)

        #expect(subject.handle(key(.keyUp, Self.spaceKeyCode, [.option])) == .consumed)
        #expect(log.releases == 1)
    }

    @Test func aRepeatingKeyDoesNotPressAgain() {
        let (subject, log) = monitor(Self.combination)
        _ = subject.handle(key(.keyDown, Self.spaceKeyCode, [.option]))

        for _ in 0..<5 {
            #expect(subject.handle(key(.keyDown, Self.spaceKeyCode, [.option], isARepeat: true)) == .consumed)
        }

        #expect(log.presses == 1)
        #expect(log.releases == 0)
    }

    @Test func aKeyTheShortcutDoesNotOwnIsHandedBackToTheApp() {
        let (subject, log) = monitor(Self.combination)

        #expect(subject.handle(key(.keyDown, Self.otherKeyCode, [.command])) == .ignored)
        #expect(subject.handle(key(.keyUp, Self.otherKeyCode, [.command])) == .ignored)
        #expect(log.presses == 0)
    }

    @Test func theRightKeyWithTheWrongModifiersIsNotTheShortcut() {
        let (subject, log) = monitor(Self.combination)

        #expect(subject.handle(key(.keyDown, Self.spaceKeyCode, [])) == .ignored)
        #expect(subject.handle(key(.keyDown, Self.spaceKeyCode, [.command])) == .ignored)
        #expect(log.presses == 0)
    }

    @Test func theKeyGoingUpEndsTheHoldEvenIfTheModifierWentFirst() {
        let (subject, log) = monitor(Self.combination)
        _ = subject.handle(key(.keyDown, Self.spaceKeyCode, [.option]))

        #expect(subject.handle(key(.keyUp, Self.spaceKeyCode, [])) == .consumed)

        #expect(log.releases == 1)
    }

    @Test func aKeyGoingUpWithoutHavingGoneDownReleasesNothing() {
        let (subject, log) = monitor(Self.combination)

        _ = subject.handle(key(.keyUp, Self.spaceKeyCode, [.option]))

        #expect(log.releases == 0)
    }

    // MARK: - A modifier held on its own

    @Test func holdingTheModifierPressesAndLettingGoReleases() {
        let (subject, log) = monitor(Self.modifierOnly)

        _ = subject.handle(key(.flagsChanged, Self.optionKeyCode, [.option]))
        #expect(log.presses == 1)

        _ = subject.handle(key(.flagsChanged, Self.optionKeyCode, []))
        #expect(log.releases == 1)
    }

    @Test func modifierEventsAreNeverSwallowed() {
        let (subject, _) = monitor(Self.modifierOnly)

        #expect(subject.handle(key(.flagsChanged, Self.optionKeyCode, [.option])) == .ignored)
        #expect(subject.handle(key(.flagsChanged, Self.optionKeyCode, [])) == .ignored)
    }

    @Test func anotherModifierDoesNotStartAHold() {
        let (subject, log) = monitor(Self.modifierOnly)

        _ = subject.handle(key(.flagsChanged, 55, [.command]))

        #expect(log.presses == 0)
    }

    @Test func aModifierHeldDownTwiceOverPressesOnlyOnce() {
        let (subject, log) = monitor(Self.modifierOnly)

        _ = subject.handle(key(.flagsChanged, Self.optionKeyCode, [.option]))
        _ = subject.handle(key(.flagsChanged, Self.optionKeyCode, [.option]))

        #expect(log.presses == 1)
    }

    // MARK: - Holds that have to be broken

    @Test func losingARequiredModifierEndsTheHold() {
        let (subject, log) = monitor(Self.combination)
        _ = subject.handle(key(.keyDown, Self.spaceKeyCode, [.option]))

        _ = subject.handle(key(.flagsChanged, Self.optionKeyCode, []))

        #expect(log.releases == 1)
    }

    @Test func aModifierChangeThatKeepsTheShortcutIntactDoesNotEndTheHold() {
        let (subject, log) = monitor(Self.combination)
        _ = subject.handle(key(.keyDown, Self.spaceKeyCode, [.option]))

        _ = subject.handle(key(.flagsChanged, 56, [.option, .shift]))

        #expect(log.releases == 0)
    }

    // MARK: - Suspending

    @Test func suspendingWhileHeldReleasesTheHold() {
        let (subject, log) = monitor(Self.combination)
        _ = subject.handle(key(.keyDown, Self.spaceKeyCode, [.option]))

        subject.setSuspended(true)

        #expect(log.releases == 1)
    }

    @Test func suspendingWhileIdleReleasesNothing() {
        let (subject, log) = monitor(Self.combination)

        subject.setSuspended(true)

        #expect(log.releases == 0)
    }

    @Test func aSuspendedMonitorSwallowsNothingAndPressesNothing() {
        let (subject, log) = monitor(Self.combination)
        subject.setSuspended(true)

        #expect(subject.handle(key(.keyDown, Self.spaceKeyCode, [.option])) == .ignored)
        #expect(log.presses == 0)
    }

    @Test func suspendingTwiceReleasesOnlyOnce() {
        let (subject, log) = monitor(Self.combination)
        _ = subject.handle(key(.keyDown, Self.spaceKeyCode, [.option]))

        subject.setSuspended(true)
        subject.setSuspended(true)

        #expect(log.releases == 1)
    }

    @Test func comingBackDoesNotResumeAHold() {
        let (subject, log) = monitor(Self.combination)
        _ = subject.handle(key(.keyDown, Self.spaceKeyCode, [.option]))
        subject.setSuspended(true)

        subject.setSuspended(false)

        #expect(log.presses == 1)
        #expect(log.releases == 1)
    }

    @Test func theShortcutWorksAgainAfterComingBack() {
        let (subject, log) = monitor(Self.combination)
        subject.setSuspended(true)
        subject.setSuspended(false)

        _ = subject.handle(key(.keyDown, Self.spaceKeyCode, [.option]))

        #expect(log.presses == 1)
    }

    // MARK: - Rebinding

    @Test func rebindingWhileHeldLetsGoFirst() {
        var shortcut = Self.combination
        let log = Log()
        let subject = HoldToTalkMonitor(talk: { shortcut })
        subject.onPress = { log.presses += 1 }
        subject.onRelease = { log.releases += 1 }
        _ = subject.handle(key(.keyDown, Self.spaceKeyCode, [.option]))

        shortcut = Self.modifierOnly
        subject.reload()

        #expect(log.releases == 1)
    }

    @Test func theNewShortcutIsTheOneThatFiresAfterwards() {
        var shortcut = Self.combination
        let log = Log()
        let subject = HoldToTalkMonitor(talk: { shortcut })
        subject.onPress = { log.presses += 1 }

        shortcut = Self.modifierOnly
        subject.reload()

        #expect(subject.handle(key(.keyDown, Self.spaceKeyCode, [.option])) == .ignored)
        _ = subject.handle(key(.flagsChanged, Self.optionKeyCode, [.option]))
        #expect(log.presses == 1)
    }
}
