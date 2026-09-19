// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct AssistantTextEditor: NSViewRepresentable {
    @Binding var text: String
    let chips: [MentionChip]
    let placeholder: String
    let fontSize: CGFloat
    let isFocused: Bool
    let showsMentions: Bool
    var onFocusChange: (Bool) -> Void
    var onChipsChange: ([UUID]) -> Void
    var onSubmit: () -> Void
    var onCancel: () -> Void
    var onMove: (Int, Bool) -> Void
    var onAttachmentPaste: ((NSPasteboard) -> Bool)?

    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> AssistantEditorScrollView {
        let scroll = AssistantEditorScrollView()
        scroll.editor.delegate = context.coordinator
        return scroll
    }

    func updateNSView(_ scroll: AssistantEditorScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        let editor = scroll.editor
        editor.onAttachmentPaste = onAttachmentPaste
        editor.onSubmit = onSubmit
        editor.onFocusChange = onFocusChange
        editor.placeholder = placeholder
        editor.setAccessibilityLabel(placeholder)
        editor.font = .systemFont(ofSize: fontSize)
        editor.typingAttributes = MentionFieldRendering.baseAttributes(fontSize: fontSize)
        let dark = colorScheme == .dark
        scroll.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        coordinator.apply(to: editor, isDark: dark)
        coordinator.syncFocus(in: editor)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: AssistantEditorScrollView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return CGSize(width: width, height: nsView.fittedHeight(for: width))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AssistantTextEditor
        private var renderedChips: [MentionChip] = []
        private var renderedDark: Bool?
        private var requestedHosts: Set<String> = []
        private var syncingFocus = false

        init(parent: AssistantTextEditor) {
            self.parent = parent
        }

        func apply(to editor: AssistantInputTextView, isDark: Bool, refresh: Bool = false) {
            guard !editor.hasMarkedText() else { return }
            loadIcons(in: editor)
            let changed = editor.string != parent.text
            guard changed || renderedChips != parent.chips || renderedDark != isDark || refresh else { return }
            let selection = editor.selectedRange()
            editor.textStorage?.setAttributedString(MentionFieldRendering.attributed(
                text: parent.text, chips: parent.chips, fontSize: parent.fontSize, isDark: isDark
            ))
            renderedChips = parent.chips
            renderedDark = isDark
            let length = (editor.string as NSString).length
            editor.setSelectedRange(changed ? NSRange(location: length, length: 0) : NSRange(
                location: min(selection.location, length),
                length: min(selection.length, max(0, length - selection.location))
            ))
            editor.needsDisplay = true
            editor.invalidateIntrinsicContentSize()
            if changed {
                editor.scrollRangeToVisible(editor.selectedRange())
            }
        }

        private func loadIcons(in editor: AssistantInputTextView) {
            let hosts = Set(parent.chips.compactMap(\.host)).filter {
                FaviconLoader.shared.cached(for: $0) == nil && !requestedHosts.contains($0)
            }
            guard !hosts.isEmpty else { return }
            requestedHosts.formUnion(hosts)
            Task { [weak self, weak editor] in
                for host in hosts {
                    _ = await FaviconLoader.shared.load(forHost: host)
                }
                guard let self, let editor else { return }
                apply(to: editor, isDark: parent.colorScheme == .dark, refresh: true)
            }
        }

        func syncFocus(in editor: AssistantInputTextView) {
            guard !syncingFocus else { return }
            syncingFocus = true
            DispatchQueue.main.async { [weak self, weak editor] in
                guard let self else { return }
                defer { syncingFocus = false }
                guard let editor, let window = editor.window else { return }
                if parent.isFocused, window.firstResponder !== editor {
                    window.makeFirstResponder(editor)
                } else if !parent.isFocused, window.firstResponder === editor {
                    window.makeFirstResponder(nil)
                }
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? AssistantInputTextView else { return }
            if !editor.hasMarkedText() {
                MentionFieldRendering.stripPastedStyles(in: editor, fontSize: parent.fontSize)
            }
            editor.typingAttributes = MentionFieldRendering.baseAttributes(fontSize: parent.fontSize)
            parent.text = editor.string
            parent.onChipsChange(MentionFieldRendering.mentionIDs(in: editor.attributedString()))
            editor.needsDisplay = true
            editor.invalidateIntrinsicContentSize()
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard parent.showsMentions else { return false }
            switch selector {
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
            case #selector(NSResponder.moveUp(_:)):
                parent.onMove(-1, false)
            case #selector(NSResponder.moveDown(_:)):
                parent.onMove(1, false)
            case #selector(NSResponder.moveToBeginningOfDocument(_:)):
                parent.onMove(-1, true)
            case #selector(NSResponder.moveToEndOfDocument(_:)):
                parent.onMove(1, true)
            default:
                return false
            }
            return true
        }
    }
}

final class AssistantEditorScrollView: NSScrollView {
    let editor = AssistantInputTextView()

    init() {
        super.init(frame: .zero)
        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        editor.drawsBackground = false
        editor.isRichText = true
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.textContainerInset = .zero
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.heightTracksTextView = false
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticTextCompletionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.writingToolsBehavior = .none
        editor.registerForDraggedTypes([.fileURL, .png, .tiff])
        documentView = editor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func fittedHeight(for width: CGFloat) -> CGFloat {
        let storage = NSTextStorage(attributedString: editor.attributedString())
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        let line = ceil(layout.defaultLineHeight(for: editor.font ?? .systemFont(ofSize: 12.5)))
        let content = ceil(max(layout.usedRect(for: container).maxY, layout.extraLineFragmentRect.maxY))
        return min(max(content, line), line * 6)
    }
}

final class AssistantInputTextView: NSTextView {
    var onAttachmentPaste: ((NSPasteboard) -> Bool)?
    var onSubmit: () -> Void = {}
    var onFocusChange: (Bool) -> Void = { _ in }
    var placeholder = "" {
        didSet { needsDisplay = true }
    }

    override func paste(_ sender: Any?) {
        guard onAttachmentPaste?(NSPasteboard.general) != true else { return }
        super.paste(sender)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if onAttachmentPaste != nil,
           sender.draggingPasteboard.availableType(from: [.fileURL, .png, .tiff]) != nil {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if onAttachmentPaste?(sender.draggingPasteboard) == true {
            return true
        }
        return super.performDragOperation(sender)
    }

    override func keyDown(with event: NSEvent) {
        if !hasMarkedText(), event.keyCode == 36 || event.keyCode == 76 {
            if event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.option) {
                insertText("\n", replacementRange: selectedRange())
            } else {
                onSubmit()
            }
            return
        }
        super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            onFocusChange(true)
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted {
            onFocusChange(false)
        }
        return accepted
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        (placeholder as NSString).draw(at: textContainerOrigin, withAttributes: [
            .font: NSFont.systemFont(ofSize: max(11, (font?.pointSize ?? 12.5) - 0.5), weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }
}
