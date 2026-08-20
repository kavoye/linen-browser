// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import Testing

@testable import Linen

@MainActor
struct MentionFieldTests {
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

    private final class Harness {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 400, height: 40),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 400, height: 24))
        var text = ""
        lazy var coordinator = MentionField.Coordinator(
            text: Binding(get: { self.text }, set: { self.text = $0 })
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

    private func harness() -> Harness {
        Harness()
    }
}
