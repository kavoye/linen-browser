// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct ToolbarSearchField: View {
    @Binding var query: String
    let placeholder: LocalizedStringResource
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(Theme.Font.label)
                .foregroundStyle(.tertiary)
            TextField("", text: $query)
                .fieldPlaceholder(placeholder, isShowing: query.isEmpty)
                .textFieldStyle(.plain)
                .font(Theme.Font.row)
                .focused($isFocused)
                .accessibilityLabel(Text(placeholder))
            if !query.isEmpty {
                ChromeIcon(symbol: "xmark", size: 9, extent: 18, help: String(localized: "Clear Search")) {
                    query = ""
                    isFocused = true
                }
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .frame(maxWidth: 240)
        .glassSurface(
            in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        )
    }
}
