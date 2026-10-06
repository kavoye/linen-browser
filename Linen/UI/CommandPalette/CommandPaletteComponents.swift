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
    let searchSite: SearchEngine?
    let suggestedSite: SearchEngine?
    let onActivateSite: () -> Bool
    let onRemoveSite: () -> Bool

    @State private var closeHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            if let searchSite {
                CommandPaletteSiteChip(site: searchSite) {
                    _ = onRemoveSite()
                    focused = true
                }
            }

            MentionField(
                text: $query,
                chips: chips,
                placeholder: placeholder,
                fontSize: 19,
                isFocused: focused,
                accessibilityLabel: searchSite.map { String(localized: "Search \($0.name)") }
                    ?? String(localized: "Search tabs, history, and actions"),
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
                },
                onTab: onActivateSite,
                onDeleteBackward: onRemoveSite
            )

            if let suggestedSite {
                CommandPaletteSiteHint(site: suggestedSite) {
                    _ = onActivateSite()
                    focused = true
                }
            }

            Button {
                if query.isEmpty && searchSite == nil {
                    onDismiss()
                } else {
                    query = ""
                    onChipsChange([])
                    _ = onRemoveSite()
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
            .help(query.isEmpty && searchSite == nil ? Text("Close (esc)") : Text("Clear"))
            .accessibilityLabel(query.isEmpty && searchSite == nil ? Text("Close") : Text("Clear"))
        }
        .padding(.horizontal, 20)
    }
}

private struct CommandPaletteSiteChip: View {
    let site: SearchEngine
    let onRemove: () -> Void

    var body: some View {
        let appearance = SiteSearchAppearance(site: site)

        Button(action: onRemove) {
            Text(site.name)
                .lineLimit(1)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(appearance.foreground)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(appearance.background, in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Remove \(site.name) search")
        .accessibilityLabel("Remove \(site.name) search")
    }
}

private struct CommandPaletteSiteHint: View {
    let site: SearchEngine
    let onActivate: () -> Void

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: 6) {
                Text("Search \(site.name)")
                    .lineLimit(1)
                Text("Tab")
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: .rect(cornerRadius: 4))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search \(site.name)")
        .accessibilityHint("Press Tab to search this site")
    }
}

struct CommandPaletteResultsView: View {
    let sections: [OmniboxSection]
    let query: String
    let selection: Int
    let optionHeld: Bool
    let maxHeight: CGFloat
    let onSelect: (Int) -> Void
    let onRun: (Int) -> Void
    let onRunAlternate: (Int) -> Void

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
                            optionHeld: optionHeld,
                            insetsVertically: false,
                            onSelect: onSelect,
                            onRun: onRun,
                            onRunAlternate: onRunAlternate,
                            alternateClickModifier: .option
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
