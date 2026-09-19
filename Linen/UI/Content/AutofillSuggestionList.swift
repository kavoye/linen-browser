// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

enum AutofillSuggestionLayout {
    static let footerHeight: CGFloat = 34
    static let rowHeight: CGFloat = 46
    static let rowSpacing: CGFloat = 2
    static let listPadding: CGFloat = 5
    static let chromeHeight = footerHeight + 1
    static let minimumHeight = chromeHeight + rowHeight + listPadding * 2

    static func height(for count: Int) -> CGFloat {
        let rows = CGFloat(max(1, min(count, 5)))
        return chromeHeight + listPadding * 2 + rows * rowHeight + (rows - 1) * rowSpacing
    }
}

@Observable
final class AutofillSuggestionSelection {
    var keyboardID: UUID?
}

struct AutofillSuggestionList: View {
    let kind: AutofillSaveKind
    let origin: String
    let suggestions: [AutofillSuggestion]
    let selection: AutofillSuggestionSelection
    let choose: (UUID) -> Void
    let manage: () -> Void

    private var symbol: String {
        switch kind {
        case .password:
            "key"
        case .card:
            "creditcard"
        case .contact:
            "person.crop.rectangle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: AutofillSuggestionLayout.rowSpacing) {
                        ForEach(suggestions) { suggestion in
                            AutofillSuggestionRow(
                                suggestion: suggestion, symbol: symbol,
                                selected: selection.keyboardID == suggestion.id,
                                choose: { choose(suggestion.id) }
                            )
                            .id(suggestion.id)
                        }
                    }
                    .padding(AutofillSuggestionLayout.listPadding)
                }
                .onChange(of: selection.keyboardID) { _, id in
                    if let id {
                        proxy.scrollTo(id)
                    }
                }
            }
            Divider()
            Button("Autofill Settings…", action: manage)
                .buttonStyle(.plain).focusable(false).font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).frame(height: AutofillSuggestionLayout.footerHeight)
        }
        .background(.regularMaterial, in: .rect(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.12)) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Autofill suggestions for \(origin)")
    }
}

private struct AutofillSuggestionRow: View {
    let suggestion: AutofillSuggestion
    let symbol: String
    let selected: Bool
    let choose: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 20).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: suggestion.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if !suggestion.detail.isEmpty {
                        Text(verbatim: suggestion.detail).font(.system(size: 11)).lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: AutofillSuggestionLayout.rowHeight)
            .contentShape(.rect)
            .background(selected || hovered ? Color.accentColor.opacity(0.18) : .clear, in: .rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovered = $0 }
    }
}
