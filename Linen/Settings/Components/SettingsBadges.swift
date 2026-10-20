// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

// MARK: - Status

enum StatusLevel {
    case ready
    case attention
    case idle

    var color: Color {
        switch self {
        case .ready:
            .green
        case .attention:
            Theme.warning
        case .idle:
            .secondary
        }
    }
}

struct StatusDot: View {
    let level: StatusLevel
    var haloed = true

    init(_ level: StatusLevel, haloed: Bool = true) {
        self.level = level
        self.haloed = haloed
    }

    var body: some View {
        Circle()
            .fill(level.color)
            .frame(width: 6, height: 6)
            .overlay(
                Circle()
                    .stroke(level.color.opacity(haloed ? 0.25 : 0), lineWidth: 3)
            )
    }
}

struct Tag: View {
    let text: LocalizedStringResource

    init(_ text: LocalizedStringResource) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .settingsSurface(in: Capsule())
            .fixedSize()
    }
}

struct SettingsNotice: View {
    let symbol: String
    let text: String
    var level: StatusLevel = .attention

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 9.5))
                .padding(.top, 1.5)
            Text(verbatim: text)
        }
        .font(Theme.Font.label)
        .foregroundStyle(level.color)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct Footnote: View {
    let text: LocalizedStringResource

    init(_ text: LocalizedStringResource) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Theme.Font.label)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, -20)
    }
}
