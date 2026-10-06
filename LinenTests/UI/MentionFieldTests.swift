// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import Testing

@testable import Linen

@MainActor
struct MentionFieldTests {
    @Test func siteChipKeyboardChangesKeepThePaletteReadyForTyping() async throws {
        let coordinator = AppCoordinator()
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1000, height: 800),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: CommandPalette(
            browser: coordinator.browser, coordinator: coordinator,
            containerSize: CGSize(width: 1000, height: 800), dismiss: {}
        ))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        #expect(await waitUntil { self.mentionField(in: host)?.currentEditor() != nil })
        let field = try #require(mentionField(in: host))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.insertText("you", replacementRange: NSRange(location: 0, length: 0))
        host.layoutSubtreeIfNeeded()
        editor.doCommand(by: #selector(NSResponder.insertTab(_:)))
        #expect(await waitUntil { field.placeholderAttributedString?.string == String(localized: "Search \("YouTube")") })
        await settlePaletteLayout(host)
        #expect(window.firstResponder === field.currentEditor())
        let searchEditor = try #require(field.currentEditor() as? NSTextView)
        searchEditor.insertText("music", replacementRange: NSRange(location: 0, length: 0))
        #expect(field.stringValue == "music")

        searchEditor.insertText("", replacementRange: NSRange(location: 0, length: searchEditor.string.utf16.count))
        host.layoutSubtreeIfNeeded()
        searchEditor.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        #expect(await waitUntil { field.placeholderAttributedString?.string != String(localized: "Search \("YouTube")") })
        await settlePaletteLayout(host)
        #expect(window.firstResponder === field.currentEditor())
        let normalEditor = try #require(field.currentEditor() as? NSTextView)
        normalEditor.insertText("next query", replacementRange: NSRange(location: 0, length: 0))
        #expect(field.stringValue == "next query")
        window.makeFirstResponder(nil)
        await settlePaletteLayout(host)
        #expect(field.currentEditor() == nil)
    }

    private func settlePaletteLayout(_ host: NSView) async {
        host.layoutSubtreeIfNeeded()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                host.layoutSubtreeIfNeeded()
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    @Test func sitePlaceholderUpdatesWhileClearingTheFocusedField() async throws {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 500, height: 40),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: MentionField(
            text: .constant("you"), placeholder: "Search tabs, history, actions, or the web",
            fontSize: 19, isFocused: true
        ))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let field = try #require(mentionField(in: host))
        #expect(await waitUntil { field.currentEditor() != nil })
        let editor = try #require(field.currentEditor())

        host.rootView = MentionField(
            text: .constant(""), placeholder: "Search YouTube", fontSize: 19, isFocused: true
        )
        host.layoutSubtreeIfNeeded()
        #expect(await waitUntil {
            field.placeholderAttributedString?.string == "Search YouTube" && editor.string.isEmpty
        })
        #expect(window.firstResponder === editor)
        let updated = try placeholderImage(in: host)

        // Refocusing makes AppKit reload the current placeholder. It should already look the same.
        window.makeFirstResponder(nil)
        window.makeFirstResponder(field)
        #expect(updated == (try placeholderImage(in: host)))
    }

    private func mentionField(in view: NSView) -> MentionTextField? {
        if let field = view as? MentionTextField {
            return field
        }
        return view.subviews.lazy.compactMap { mentionField(in: $0) }.first
    }

    private func placeholderImage(in view: NSView) throws -> Data {
        view.displayIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    @Test func aComposedMentionLeavesTheCaretAtTheEnd() {
        let harness = harness()
        harness.field.stringValue = "which is cheaper @ni"
        harness.window.makeFirstResponder(harness.field)
        let editor = harness.field.currentEditor() as? NSTextView
        editor?.selectedRange = NSRange(location: 0, length: 20)

        let chip = MentionChip(id: UUID(), title: "Nike Air Max")
        harness.coordinator.apply(
            text: "which is cheaper \(MentionText.marker) ",
            chips: [chip],
            isDark: true,
            to: harness.field
        )

        let selection = (harness.field.currentEditor() as? NSTextView)?.selectedRange()
        #expect(selection?.length == 0)
        #expect(selection?.location == harness.field.attributedStringValue.length)
    }

    @Test func theAddressCommandStillSelectsTheWholeAddress() {
        let harness = harness()
        harness.window.makeFirstResponder(harness.field)
        harness.coordinator.apply(
            text: "https://example.com/path",
            chips: [],
            isDark: true,
            to: harness.field
        )

        harness.coordinator.selectAll(token: 1, in: harness.field)

        let selection = (harness.field.currentEditor() as? NSTextView)?.selectedRange()
        #expect(selection?.location == 0)
        #expect(selection?.length == harness.field.attributedStringValue.length)
    }

    @Test func deletingAChipReportsTheRemainingTabsInOrder() {
        let harness = harness()
        let first = MentionChip(id: UUID(), title: "Nike Air Max")
        let second = MentionChip(id: UUID(), title: "Adidas Samba")
        var reported: [UUID] = []
        harness.coordinator.onChipsChange = { reported = $0 }
        harness.window.makeFirstResponder(harness.field)
        harness.coordinator.apply(
            text: "compare \(MentionText.marker) with \(MentionText.marker)",
            chips: [first, second],
            isDark: true,
            to: harness.field
        )

        let editor = harness.field.currentEditor() as? NSTextView
        editor?.replaceCharacters(in: NSRange(location: 8, length: 1), with: "")
        harness.coordinator.controlTextDidChange(
            Notification(name: NSControl.textDidChangeNotification, object: harness.field)
        )

        #expect(reported == [second.id])
        #expect(MentionText.count(in: harness.text) == 1)
    }

    @Test func chipsRenderAsAttachmentsCarryingTheirTabID() {
        let chip = MentionChip(id: UUID(), title: "Nike Air Max")
        let attributed = MentionFieldRendering.attributed(
            text: "compare \(MentionText.marker)",
            chips: [chip],
            fontSize: 13,
            isDark: false
        )

        #expect(attributed.string == "compare \(MentionText.marker)")
        #expect(MentionFieldRendering.mentionIDs(in: attributed) == [chip.id])
        let attachment = attributed.attribute(
            .attachment,
            at: attributed.length - 1,
            effectiveRange: nil
        ) as? NSTextAttachment
        #expect(attachment?.image != nil)
        #expect((attachment?.bounds.width ?? 0) > 0)
    }

    /// A link copied from a page carries the website's own styling. Pasted into
    /// the address field it used to stay blue and underlined.
    @Test func aPastedLinkLosesTheWebsitesStyling() throws {
        let harness = harness()
        harness.window.makeFirstResponder(harness.field)
        let editor = try #require(harness.field.currentEditor() as? NSTextView)
        let storage = try #require(editor.textStorage)

        storage.setAttributedString(NSAttributedString(
            string: "https://example.com/article",
            attributes: [
                .link: URL(string: "https://example.com/article") as Any,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: NSColor.systemBlue,
                .font: NSFont.systemFont(ofSize: 24),
            ]
        ))
        harness.coordinator.controlTextDidChange(
            Notification(name: NSControl.textDidChangeNotification, object: harness.field)
        )

        let styled = editor.attributedString()
        var attributes: [NSAttributedString.Key: Any] = [:]
        attributes = styled.attributes(at: 0, effectiveRange: nil)
        #expect(attributes[.link] == nil)
        #expect(attributes[.underlineStyle] == nil)
        #expect(attributes[.foregroundColor] as? NSColor == .labelColor)
        #expect((attributes[.font] as? NSFont)?.pointSize == 13)
        #expect(harness.text == "https://example.com/article")
    }

    /// The chips are attachments. Cleaning a pasted run must not flatten them.
    @Test func cleaningAPasteLeavesTheChipsAlone() throws {
        let harness = harness()
        let chip = MentionChip(id: UUID(), title: "Nike Air Max")
        harness.window.makeFirstResponder(harness.field)
        harness.coordinator.apply(
            text: "compare \(MentionText.marker)",
            chips: [chip],
            isDark: false,
            to: harness.field
        )

        let editor = try #require(harness.field.currentEditor() as? NSTextView)
        MentionFieldRendering.stripPastedStyles(in: editor, fontSize: 13)

        #expect(MentionFieldRendering.mentionIDs(in: editor.attributedString()) == [chip.id])
    }

    /// AppKit offers ⌘↩ round as a key equivalent and beeps when nothing takes
    /// it, so the field editor never sees it. The field claims it instead.
    @Test func commandReturnReachesTheAssistant() throws {
        let harness = harness()
        var asked = 0
        harness.field.onCommandReturn = { asked += 1 }
        harness.window.makeFirstResponder(harness.field)

        #expect(harness.field.performKeyEquivalent(with: try returnKey(.command, in: harness)))
        #expect(asked == 1)
    }

    @Test func aPlainReturnIsLeftToTheFieldEditor() throws {
        let harness = harness()
        var asked = 0
        harness.field.onCommandReturn = { asked += 1 }
        harness.window.makeFirstResponder(harness.field)

        #expect(!harness.field.performKeyEquivalent(with: try returnKey([], in: harness)))
        #expect(!harness.field.performKeyEquivalent(with: try returnKey([.command, .shift], in: harness)))
        #expect(asked == 0)
    }

    @Test func anUnfocusedFieldDoesNotAnswerForTheWindow() throws {
        let harness = harness()
        var asked = 0
        harness.field.onCommandReturn = { asked += 1 }
        harness.window.makeFirstResponder(nil)

        #expect(!harness.field.performKeyEquivalent(with: try returnKey(.command, in: harness)))
        #expect(asked == 0)
    }

    @Test func tabIsHandledOnlyWhenASiteCanBeActivated() {
        let harness = harness()
        let editor = NSTextView()
        let tab = #selector(NSResponder.insertTab(_:))
        #expect(!harness.coordinator.control(harness.field, textView: editor, doCommandBy: tab))
        harness.coordinator.onTab = { true }
        #expect(harness.coordinator.control(harness.field, textView: editor, doCommandBy: tab))
        #expect(!harness.coordinator.control(
            harness.field, textView: editor, doCommandBy: #selector(NSResponder.insertBacktab(_:))
        ))
        editor.setMarkedText("よ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: 0, length: 0))
        #expect(!harness.coordinator.control(harness.field, textView: editor, doCommandBy: tab))
    }

    @Test func backspaceRemovesSiteOnlyWhenTheFieldIsEmpty() {
        let harness = harness()
        let editor = NSTextView()
        let backspace = #selector(NSResponder.deleteBackward(_:))
        var removed = false
        harness.coordinator.onDeleteBackward = {
            removed = true
            return true
        }
        editor.string = "query"
        #expect(!harness.coordinator.control(harness.field, textView: editor, doCommandBy: backspace))
        #expect(!removed)
        editor.string = ""
        #expect(harness.coordinator.control(harness.field, textView: editor, doCommandBy: backspace))
        #expect(removed)
    }

    private func returnKey(_ modifiers: NSEvent.ModifierFlags, in harness: Harness) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: harness.window.windowNumber,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ))
    }

    fileprivate final class Harness {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 400, height: 40),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let field = MentionTextField(frame: CGRect(x: 0, y: 0, width: 400, height: 24))
        var text = ""
        lazy var coordinator = MentionField.Coordinator(
            text: Binding(
                get: { MainActor.assumeIsolated { self.text } },
                set: { value in MainActor.assumeIsolated { self.text = value } }
            )
        )

        init() {
            field.isBordered = false
            field.drawsBackground = false
            field.allowsEditingTextAttributes = true
            field.font = .systemFont(ofSize: 13)
            field.cell?.wraps = false
            field.cell?.isScrollable = true
            field.delegate = coordinator
            window.contentView?.addSubview(field)
        }
    }

    fileprivate func harness() -> Harness {
        Harness()
    }
}
