// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct KeyCap: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, text.count > 1 ? 5 : 0)
            .frame(minWidth: 18, minHeight: 18)
            .background(
                Theme.Wash.selection,
                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
            )
            .fixedSize()
    }
}

struct KeyCaps: View {
    let caps: [String]

    init(_ shortcut: String) {
        caps = shortcut.map(String.init)
    }

    init(caps: [String]) {
        self.caps = caps
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(caps.enumerated(), id: \.offset) { _, cap in
                KeyCap(cap)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: caps.joined()))
    }
}
