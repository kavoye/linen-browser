// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

enum AutofillSuggestionLayout {
    static let footerHeight: CGFloat = 24
    static let rowHeight: CGFloat = 42
    static let rowSpacing: CGFloat = 0
    static let listPadding: CGFloat = 5
    static let cornerRadius: CGFloat = 10
    static let chromeHeight = footerHeight + 1 + listPadding * 2
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

    @State private var hoveredID: UUID?
    @State private var footerHovered = false

    private var highlightedID: UUID? {
        footerHovered ? nil : hoveredID ?? selection.keyboardID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: AutofillSuggestionLayout.rowSpacing) {
                        ForEach(suggestions) { suggestion in
                            AutofillSuggestionRow(
                                suggestion: suggestion, symbol: symbol,
                                highlighted: highlightedID == suggestion.id,
                                choose: { choose(suggestion.id) },
                                hover: { inside in
                                    if inside {
                                        hoveredID = suggestion.id
                                    } else if hoveredID == suggestion.id {
                                        hoveredID = nil
                                    }
                                }
                            )
                            .id(suggestion.id)
                        }
                    }
                    .padding(AutofillSuggestionLayout.listPadding)
                }
                .scrollIndicators(.never)
                .onChange(of: selection.keyboardID) { _, id in
                    if let id {
                        hoveredID = nil
                        proxy.scrollTo(id)
                    }
                }
            }
            Divider().padding(.horizontal, AutofillSuggestionLayout.listPadding + 9)
            Button(action: manage) {
                Text("Autofill Settings…")
                    .font(.system(size: 13))
                                        .padding(.horizontal, 9)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(.rect)
                    .background(footerHovered ? Color.primary.opacity(0.1) : .clear, in: .rect(cornerRadius: 5))
            }
            .buttonStyle(.plain).focusable(false)
            .frame(height: AutofillSuggestionLayout.footerHeight)
            .padding([.horizontal, .bottom], AutofillSuggestionLayout.listPadding)
            .padding(.top, AutofillSuggestionLayout.listPadding)
            .onHover { footerHovered = $0 }
        }
        .background { VisualEffectView(material: .menu) }
        .clipShape(.rect(cornerRadius: AutofillSuggestionLayout.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AutofillSuggestionLayout.cornerRadius)
                .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Autofill suggestions for \(origin)")
    }
}

private struct AutofillSuggestionRow: View {
    let suggestion: AutofillSuggestion
    let symbol: String
    let highlighted: Bool
    let choose: () -> Void
    let hover: (Bool) -> Void

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .symbolVariant(.fill)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: suggestion.title).font(.system(size: 13)).lineLimit(1)
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
            .background(highlighted ? Color.primary.opacity(0.1) : .clear, in: .rect(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover(perform: hover)
    }
}
