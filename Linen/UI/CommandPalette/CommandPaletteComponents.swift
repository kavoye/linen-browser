// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct CommandPaletteField: View {
    let placeholder: String
    @Binding var query: String
    let chips: [MentionChip]
    @Binding var focused: Bool
    let onSubmit: () -> Void
    let onCommandSubmit: () -> Void
    let onMoveSelection: (Int) -> Void
    let onMoveSection: (Int) -> Void
    let onChipsChange: ([UUID]) -> Void
    let onDismiss: () -> Void

    @State private var closeHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            MentionField(
                text: $query,
                chips: chips,
                placeholder: placeholder,
                fontSize: 19,
                isFocused: focused,
                accessibilityLabel: String(localized: "Search tabs, history, and actions"),
                onFocusChange: { focused = $0 },
                onChipsChange: onChipsChange,
                onSubmit: onSubmit,
                onCommandSubmit: onCommandSubmit,
                onCancel: onDismiss,
                onMove: { delta, bySection in
                    if bySection {
                        onMoveSection(delta)
                    } else {
                        onMoveSelection(delta)
                    }
                }
            )

            Button {
                if query.isEmpty {
                    onDismiss()
                } else {
                    query = ""
                    onChipsChange([])
                    focused = true
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(closeHovering ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { closeHovering = $0 }
            .help(query.isEmpty ? Text("Close (esc)") : Text("Clear"))
            .accessibilityLabel(query.isEmpty ? Text("Close") : Text("Clear"))
        }
        .padding(.horizontal, 20)
    }
}

struct CommandPaletteResultsView: View {
    let sections: [OmniboxSection]
    let query: String
    let selection: Int
    let maxHeight: CGFloat
    let onSelect: (Int) -> Void
    let onRun: (Int) -> Void

    var body: some View {
        if !sections.isEmpty {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Theme.Wash.hover)
                    .frame(height: 1)
                    .accessibilityHidden(true)

                ScrollViewReader { proxy in
                    ScrollView {
                        OmniboxList(
                            sections: sections,
                            query: query,
                            selection: selection,
                            insetsVertically: false,
                            onSelect: onSelect,
                            onRun: onRun
                        )
                    }
                    .contentMargins(.vertical, OmniboxList.Density.regular.padding, for: .scrollContent)
                    .frame(height: min(maxHeight, OmniboxList.height(of: sections, density: .regular)))
                    .onChange(of: selection) { _, index in
                        proxy.scrollTo(index)
                    }
                }
            }
        }
    }
}

struct CommandPaletteSuggestionSync: ViewModifier {
    let suggestions: SearchSuggestions
    let onChange: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: suggestions.phrases) {
            onChange()
        }
    }
}
