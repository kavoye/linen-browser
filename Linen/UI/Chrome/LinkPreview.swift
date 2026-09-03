// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

enum LinkIntent: Equatable {
    case open
    case peek
    case newTab

    static func of(_ flags: NSEvent.ModifierFlags) -> LinkIntent {
        let wanted = flags.intersection([.command, .shift])
        if wanted.contains(.command) {
            return .newTab
        }
        return wanted == .shift ? .peek : .open
    }
}

struct LinkPreview: View {
    let address: String?
    var intent: LinkIntent = .open
    /// What the chip stands on. Glass shows the page through it, so the ink has
    /// to be decided from the page rather than from the window's appearance.
    var ground: NSColor?
    var delay: Duration = .milliseconds(400)
    var obeysSetting = true

    @State private var shown: String?
    @Environment(\.colorScheme) private var scheme

    private var standsOnLight: Bool {
        PageInk.isLight(ground, scheme: scheme)
    }

    private var ink: Color {
        standsOnLight ? .black : .white
    }

    private var fill: Color {
        standsOnLight ? Color(white: 0.97) : Color(white: 0.15)
    }

    private func label(_ address: String) -> AttributedString {
        switch intent {
        case .open:
            return AttributedString(address)
        case .peek:
            return named(String(localized: "Open \(address) in Peek"), address: address)
        case .newTab:
            return named(String(localized: "Open \(address) in a new tab"), address: address)
        }
    }

    private func named(_ sentence: String, address: String) -> AttributedString {
        var text = AttributedString(sentence)
        text.foregroundColor = ink.opacity(0.5)
        if let range = text.range(of: address) {
            text[range].foregroundColor = ink.opacity(0.92)
        }
        return text
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let shown, !obeysSetting || BrowserSettings.shared.showsLinkPreview {
                Text(label(shown))
                    .font(Theme.Font.caption)
                    .foregroundStyle(ink.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(fill, in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(ink.opacity(0.12), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(standsOnLight ? 0.1 : 0.28), radius: 6, y: 2)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
        .allowsHitTesting(false)
        .task(id: address) {
            guard let address else {
                shown = nil
                return
            }
            if shown == nil, delay > .zero {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
            }
            shown = address
        }
    }
}
