// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Testing

@testable import Linen

@MainActor
struct AssistantTextEditorTests {
    @Test func attachmentPasteLeavesTheMessageAndCaretIntact() {
        let editor = AssistantInputTextView()
        editor.string = "My question"
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        var imports = 0
        editor.onAttachmentPaste = { _ in
            imports += 1
            return true
        }
        editor.paste(nil)
        #expect(imports == 1)
        #expect(editor.string == "My question")
        #expect(editor.selectedRange().location == 3)
    }

    @Test func shiftReturnInsertsANewlineWithoutSending() throws {
        let editor = AssistantInputTextView()
        var submissions = 0
        editor.onSubmit = { submissions += 1 }
        editor.string = "firstsecond"
        editor.setSelectedRange(NSRange(location: 5, length: 0))

        editor.keyDown(with: try returnEvent(modifiers: .shift))

        #expect(editor.string == "first\nsecond")
        #expect(editor.selectedRange().location == 6)
        #expect(submissions == 0)
        editor.keyDown(with: try returnEvent(modifiers: []))
        #expect(submissions == 1)
        #expect(editor.string == "first\nsecond")
    }

    @Test func growsThenScrollsAndShrinksWhenCleared() {
        let scroll = AssistantEditorScrollView()
        scroll.editor.font = .systemFont(ofSize: 12.5)
        let empty = scroll.fittedHeight(for: 240)
        scroll.editor.string = "first\nsecond\n"
        let expanded = scroll.fittedHeight(for: 240)
        #expect(expanded > empty)
        scroll.editor.string = String(repeating: "A long message that wraps over several lines. ", count: 100)
        let capped = scroll.fittedHeight(for: 240)
        #expect(capped == empty * 6)
        scroll.frame = NSRect(x: 0, y: 0, width: 240, height: capped)
        scroll.tile()
        scroll.layoutSubtreeIfNeeded()
        scroll.editor.scrollRangeToVisible(NSRange(location: (scroll.editor.string as NSString).length, length: 0))
        #expect(scroll.editor.frame.height > scroll.contentSize.height)
        #expect(scroll.contentView.bounds.origin.y > 0)
        scroll.editor.string = ""
        #expect(scroll.fittedHeight(for: 240) == empty)
    }

    @Test func newlinePreservesMentionAttachments() throws {
        let chip = MentionChip(id: UUID(), title: "Example")
        let editor = AssistantInputTextView()
        editor.textStorage?.setAttributedString(MentionFieldRendering.attributed(
            text: MentionText.marker + " hello", chips: [chip], fontSize: 12.5, isDark: false
        ))
        editor.setSelectedRange(NSRange(location: 7, length: 0))
        editor.keyDown(with: try returnEvent(modifiers: .shift))
        #expect(editor.string == MentionText.marker + " hello\n")
        #expect(MentionFieldRendering.mentionIDs(in: editor.attributedString()) == [chip.id])
    }

    private func returnEvent(modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
        ))
    }
}
