// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Testing

@testable import Linen

struct ActivationShortcutTests {
    private static func keyEvent(
        _ keyCode: UInt16,
        _ flags: NSEvent.ModifierFlags,
        characters: String = "k"
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )
    }

    // MARK: - Persistence encoding

    @Test(arguments: [
        ActivationShortcut.optionSpace,
        ActivationShortcut(keyCode: 40, modifiers: [.command, .shift], label: "K"),
        ActivationShortcut(keyCode: 63, label: "fn"),
        ActivationShortcut(keyCode: 124, modifiers: [.control, .option], label: "→"),
        ActivationShortcut(keyCode: 61, label: "right ⌥"),
    ])
    func survivesItsOwnPersistenceEncoding(_ shortcut: ActivationShortcut) throws {
        let data = try JSONEncoder().encode(shortcut)
        let decoded = try JSONDecoder().decode(ActivationShortcut.self, from: data)
        #expect(decoded == shortcut)
    }

    /// The shape already sitting in people's defaults; changing a property
    /// name would silently reset every bound shortcut.
    @Test func decodesTheStoredShape() throws {
        let json = #"{"keyCode":61,"modifierFlags":0,"label":"right ⌥"}"#
        let decoded = try JSONDecoder().decode(ActivationShortcut.self, from: Data(json.utf8))
        #expect(decoded.keyCode == 61)
        #expect(decoded.modifiers == [])
        #expect(decoded.label == "right ⌥")
        #expect(decoded.isModifierOnly)
    }

    @Test func settingsRoundTripThroughDefaultsAndRestoreTheDefault() {
        let talkKey = "input.shortcut.talk"
        let previous = UserDefaults.standard.data(forKey: talkKey)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: talkKey)
            } else {
                UserDefaults.standard.removeObject(forKey: talkKey)
            }
        }

        let custom = ActivationShortcut(keyCode: 40, modifiers: [.command, .option], label: "K")
        ActivationSettings.talk = custom
        #expect(ActivationSettings.talk == custom)

        UserDefaults.standard.removeObject(forKey: talkKey)
        #expect(ActivationSettings.talk == ActivationSettings.defaultTalk)

        UserDefaults.standard.set(Data("not json".utf8), forKey: talkKey)
        #expect(ActivationSettings.talk == ActivationSettings.defaultTalk)
    }

    // MARK: - Shape

    @Test(arguments: [UInt16]([54, 55, 56, 58, 59, 60, 61, 62, 63]))
    func everyBareModifierCanBeHeld(_ keyCode: UInt16) throws {
        let shortcut = ActivationShortcut(keyCode: keyCode, label: "mod")
        #expect(shortcut.isModifierOnly)
        let flag = try #require(ActivationShortcut.modifierKeys[keyCode]).flag
        #expect(shortcut.isDown(in: flag))
        #expect(!shortcut.isDown(in: []))
    }

    /// The recorder refuses a bare ordinary key; if one got through anyway it
    /// must at least never read as holdable.
    @Test func anOrdinaryKeyIsNotHoldable() {
        let bare = ActivationShortcut(keyCode: 40, label: "K")
        #expect(!bare.isModifierOnly)
        #expect(!bare.isDown(in: [.command, .option, .shift, .control, .function]))
    }

    @Test func drawsModifierGlyphsInTheSystemOrder() {
        let shortcut = ActivationShortcut(
            keyCode: 40,
            modifiers: [.command, .shift, .option, .control],
            label: "K"
        )
        #expect(shortcut.caps == ["⌃", "⌥", "⇧", "⌘", "K"])
    }

    @Test func aBareModifierDrawsOnlyItsOwnCap() {
        let shortcut = ActivationShortcut(keyCode: 61, label: "right ⌥")
        #expect(shortcut.caps == [shortcut.label])
    }

    @Test func theDefaultIsAChordThatTypesNothingOnItsOwn() {
        let shortcut = ActivationSettings.defaultTalk
        #expect(!shortcut.isModifierOnly)
        #expect(shortcut.modifiers == .option)
        #expect(shortcut.caps == ["⌥", "Space"])
        #expect(shortcut.phrase == "⌥Space")
    }

    // MARK: - Refusals

    @Test func aKeyWithNoModifierIsRefused() {
        let bare = ActivationShortcut(keyCode: 40, label: "K")
        #expect(ActivationShortcut.refusal(for: bare) == .bareKey)
    }

    @Test(arguments: [
        ActivationShortcut(keyCode: 13, modifiers: [.command], label: "W"),
        ActivationShortcut(keyCode: 12, modifiers: [.command, .shift], label: "Q"),
        ActivationShortcut(keyCode: 49, modifiers: [.command, .option], label: "Space"),
    ])
    func aCommandChordIsRefused(_ shortcut: ActivationShortcut) {
        #expect(ActivationShortcut.refusal(for: shortcut) == .command)
    }

    @Test(arguments: [UInt16]([54, 55]))
    func aBareCommandKeyIsRefused(_ keyCode: UInt16) throws {
        let name = try #require(ActivationShortcut.modifierKeys[keyCode]).name
        let shortcut = ActivationShortcut(keyCode: keyCode, label: name)
        #expect(ActivationShortcut.refusal(for: shortcut) == .command)
    }

    @Test(arguments: [UInt16]([56, 58, 59, 60, 61, 62, 63]))
    func everyOtherBareModifierIsAccepted(_ keyCode: UInt16) throws {
        let name = try #require(ActivationShortcut.modifierKeys[keyCode]).name
        let shortcut = ActivationShortcut(keyCode: keyCode, label: name)
        #expect(ActivationShortcut.refusal(for: shortcut) == nil)
    }

    @Test func theDefaultIsAccepted() {
        #expect(ActivationShortcut.refusal(for: ActivationSettings.defaultTalk) == nil)
        #expect(ActivationShortcut.refusal(
            for: ActivationShortcut(keyCode: 124, modifiers: [.control, .option], label: "→")
        ) == nil)
    }

    // MARK: - Matching

    @Test func onlyTheFourRealModifiersAreSignificant() {
        let flags: NSEvent.ModifierFlags = [.option, .function, .numericPad, .capsLock]
        #expect(ActivationShortcut.significant(flags) == .option)
        #expect(ActivationShortcut.significant([]) == [])
    }

    @Test func matchesTheRecordedKeyAndModifiersExactly() throws {
        let shortcut = ActivationShortcut(keyCode: 40, modifiers: [.command], label: "K")
        #expect(shortcut.matches(try #require(Self.keyEvent(40, [.command]))))
        #expect(!shortcut.matches(try #require(Self.keyEvent(40, [.command, .shift]))))
        #expect(!shortcut.matches(try #require(Self.keyEvent(40, []))))
        #expect(!shortcut.matches(try #require(Self.keyEvent(38, [.command]))))
    }

    /// Arrows arrive carrying `.function`; the recorded shortcut must still
    /// match the pressed key.
    @Test func arrowEventsMatchDespiteTheirHiddenFunctionFlag() throws {
        let shortcut = ActivationShortcut(keyCode: 124, modifiers: [.option], label: "→")
        let event = try #require(Self.keyEvent(124, [.option, .function, .numericPad], characters: "→"))
        #expect(shortcut.matches(event))
    }

    // MARK: - Caps for pressed keys

    @Test func namesTheKeysThatPrintNothing() throws {
        let space = try #require(Self.keyEvent(49, [], characters: " "))
        #expect(ActivationShortcut.label(for: space) == "Space")
        let arrow = try #require(Self.keyEvent(123, [.function], characters: ""))
        #expect(ActivationShortcut.label(for: arrow) == "←")
    }

    @Test func uppercasesWhatTheKeyTypes() throws {
        let event = try #require(Self.keyEvent(40, [.command], characters: "k"))
        #expect(ActivationShortcut.label(for: event) == "K")
    }
}
