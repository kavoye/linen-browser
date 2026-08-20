// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit

@MainActor
enum ConfirmAlert {
    static func destructive(
        _ question: LocalizedStringResource,
        detail: LocalizedStringResource? = nil,
        verb: LocalizedStringResource
    ) async -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: question)
        if let detail {
            alert.informativeText = String(localized: detail)
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: verb)).hasDestructiveAction = true
        alert.addButton(withTitle: String(localized: "Cancel"))

        guard let window = NSApp.keyWindow else {
            return alert.runModal() == .alertFirstButtonReturn
        }
        let response = await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
        }
        return response == .alertFirstButtonReturn
    }

    static func organize(folders: [(name: String, count: Int)]) async -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Organize your tabs into folders?")
        let lines = folders.map { folder in
            "•  " + String(localized: "\(folder.name): \(folder.count) tabs")
        }
        alert.informativeText = lines.joined(separator: "\n") + "\n\n"
            + String(localized: "Tabs that don’t fit a group stay where they are.")
        alert.addButton(withTitle: String(localized: "Organize"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        guard let window = NSApp.keyWindow else {
            return alert.runModal() == .alertFirstButtonReturn
        }
        let response = await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
        }
        return response == .alertFirstButtonReturn
    }

    static func clear(_ prompt: BrowsingData.ClearPrompt) async -> BrowsingData.ClearChoice? {
        let alert = NSAlert()
        alert.messageText = String(localized: prompt.question)
        alert.informativeText = String(localized: prompt.detail)
        alert.alertStyle = .warning

        let accessory = ClearAccessory(prompt: prompt)
        alert.accessoryView = Self.textColumn(accessory.view)

        let confirm = alert.addButton(withTitle: String(localized: BrowsingData.ClearPrompt.verb))
        confirm.hasDestructiveAction = true
        alert.addButton(withTitle: String(localized: "Cancel"))
        accessory.confirmButton = confirm

        let response: NSApplication.ModalResponse
        if let window = NSApp.keyWindow {
            response = await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            }
        } else {
            response = alert.runModal()
        }

        guard response == .alertFirstButtonReturn else { return nil }
        return accessory.choice
    }

    private static func textColumn(_ control: NSView) -> NSView {
        let column: CGFloat = 244
        control.setFrameOrigin(NSPoint(x: 4, y: 0))
        let row = NSView(
            frame: NSRect(x: 0, y: 0, width: max(control.frame.width, column) + 8, height: control.frame.height)
        )
        row.addSubview(control)
        return row
    }
}

@MainActor
private final class ClearAccessory: NSObject {
    let view: NSView

    weak var confirmButton: NSButton?

    private let prompt: BrowsingData.ClearPrompt
    private let picker: NSPopUpButton
    private let boxes: [(kind: BrowsingData.Kind, button: NSButton)]

    init(prompt: BrowsingData.ClearPrompt) {
        self.prompt = prompt

        picker = NSPopUpButton(frame: .zero, pullsDown: false)
        for range in prompt.ranges {
            picker.addItem(withTitle: String(localized: range.label))
        }
        if let initial = prompt.ranges.firstIndex(of: BrowsingData.ClearPrompt.initialRange) {
            picker.selectItem(at: initial)
        }
        picker.sizeToFit()

        boxes = prompt.selectableKinds.map { kind in
            let button = NSButton(checkboxWithTitle: String(localized: kind.label), target: nil, action: nil)
            button.state = prompt.kinds.contains(kind) ? .on : .off
            return (kind, button)
        }

        let stack = NSStackView(views: [picker] + boxes.map(\.button))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setHuggingPriority(.defaultHigh, for: .vertical)
        stack.frame.size = stack.fittingSize
        view = stack

        super.init()

        for box in boxes {
            box.button.target = self
            box.button.action = #selector(kindToggled)
        }
    }

    private var kinds: Set<BrowsingData.Kind> {
        boxes.isEmpty ? prompt.kinds : Set(boxes.filter { $0.button.state == .on }.map(\.kind))
    }

    var choice: BrowsingData.ClearChoice? {
        guard prompt.ranges.indices.contains(picker.indexOfSelectedItem) else { return nil }
        let chosen = kinds
        guard !chosen.isEmpty else { return nil }
        return BrowsingData.ClearChoice(kinds: chosen, range: prompt.ranges[picker.indexOfSelectedItem])
    }

    @objc private func kindToggled() {
        confirmButton?.isEnabled = !kinds.isEmpty
    }
}
