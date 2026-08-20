// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct ShortcutRecorder: View {
    let id: String
    @Binding var recording: String?

    let shortcut: ActivationShortcut
    let defaultShortcut: ActivationShortcut
    let onChange: (ActivationShortcut) -> Void

    @State private var monitor: Any?
    @State private var heldModifier: UInt16?
    @State private var complaint: String?
    @State private var hovering = false

    private var isRecording: Bool {
        recording == id
    }
    private var isDefault: Bool {
        shortcut == defaultShortcut
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 7) {
            HStack(spacing: 7) {
                field

                if !isRecording, !isDefault {
                    IconButton(symbol: "arrow.uturn.backward", help: "Reset to Default") {
                        complaint = nil
                        onChange(defaultShortcut)
                    }
                }
            }

            if isRecording {
                Text("Press a shortcut. Press Escape to cancel.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.trailing)
            } else if let complaint {
                SettingsNotice(symbol: "exclamationmark.triangle.fill", text: complaint)
            }
        }
        .onChange(of: isRecording) { _, listening in
            if listening {
                listen()
            } else {
                deafen()
            }
        }
        .onDisappear {
            deafen()
            if isRecording {
                recording = nil
            }
        }
    }

    private var field: some View {
        Button {
            complaint = nil
            recording = isRecording ? nil : id
        } label: {
            HStack(spacing: 5) {
                if isRecording {
                    Text("Press shortcut")
                        .font(Theme.Font.secondary)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(shortcut.caps.enumerated(), id: \.offset) { _, cap in
                        KeyCap(cap)
                    }
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 28)
            .background {
                let shape = RoundedRectangle(cornerRadius: Theme.Radius.hover)
                if isRecording {
                    shape
                        .fill(Theme.danger.opacity(0.1))
                        .overlay(shape.strokeBorder(Theme.danger.opacity(0.5), lineWidth: 1))
                } else {
                    shape.fill(hovering ? Theme.Wash.hairline : Theme.Wash.none)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(isRecording ? "Cancel shortcut recording" : "Change the keyboard shortcut")
        .animation(Theme.Motion.quick, value: isRecording)
        .animation(Theme.Motion.quick, value: hovering)
    }

    // MARK: - Listening

    private func listen() {
        guard monitor == nil else { return }
        heldModifier = nil

        // Swallow every key while recording runs. If not, recording Command-W
        // closes the window being configured.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            MainActor.assumeIsolated {
                capture(event)
            }
            return nil
        }
    }

    private func deafen() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        heldModifier = nil
    }

    private func capture(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            guard let modifier = ActivationShortcut.modifierKeys[event.keyCode] else { return }
            if event.modifierFlags.contains(modifier.flag) {
                heldModifier = event.keyCode
            } else if heldModifier == event.keyCode {
                commit(ActivationShortcut(keyCode: event.keyCode, label: modifier.name))
            }

        case .keyDown:
            heldModifier = nil
            let modifiers = ActivationShortcut.significant(event.modifierFlags)

            if event.keyCode == 53, modifiers.isEmpty {
                recording = nil
                return
            }

            commit(ActivationShortcut(
                keyCode: event.keyCode,
                modifiers: modifiers,
                label: ActivationShortcut.label(for: event)
            ))

        default:
            break
        }
    }

    private func commit(_ recorded: ActivationShortcut) {
        recording = nil
        if let refusal = ActivationShortcut.refusal(for: recorded) {
            complaint = Self.complaint(for: refusal)
            return
        }
        complaint = nil
        onChange(recorded)
    }

    private static func complaint(for refusal: ActivationShortcut.Refusal) -> String {
        switch refusal {
        case .bareKey:
            String(localized: "A key on its own would fire while you type. Hold a modifier with it, or press a modifier by itself.")
        case .command:
            String(localized: "Menu commands already use ⌘ shortcuts. Hold ⌥, ⌃ or ⇧ instead.")
        }
    }
}
