// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct DestinationPage<Toolbar: View, Content: View>: View {
    @ViewBuilder let toolbar: Toolbar
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 12)
                .frame(maxWidth: 780)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 32)
                .padding(.top, 30)
                .padding(.bottom, 16)

            Divider().opacity(0.4)

            ScrollView {
                content
                    .frame(maxWidth: 780, alignment: .leading)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Theme.windowBackground
                .contentShape(Rectangle())
                .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }
        )
    }
}

struct DestinationTitle: View {
    let title: LocalizedStringResource
    let dismiss: () -> Void

    var body: some View {
        Button(action: dismiss) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .help("Back")
    }
}

struct DestinationCount: View {
    let count: Int

    var body: some View {
        Text(count, format: .number)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.Wash.hairline, in: Capsule())
    }
}
