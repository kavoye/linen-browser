// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct GitHubFilterPicker: View {
    let filters: [GitHubFilter]
    let selectedID: String
    let onSelect: @MainActor (String) -> Void
    let onNew: () -> Void
    let onEdit: (GitHubFilter) -> Void
    let onDelete: (String) -> Void
    @State private var presented = false
    @State private var hovering = false

    var body: some View {
        Button { presented.toggle() } label: {
            HStack(spacing: 6) {
                Text(verbatim: filters.first { $0.id == selectedID }?.name ?? "").lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            .font(Theme.Font.control.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(presented || hovering ? Theme.Wash.hover : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("Pull request filter")
        .accessibilityValue(filters.first { $0.id == selectedID }?.name ?? "")
        .popover(isPresented: $presented, arrowEdge: .top) {
            GitHubFilterMenu(filters: filters, selectedID: selectedID,
                             onSelect: { presented = false; onSelect($0) },
                             onNew: { presented = false; onNew() },
                             onEdit: { presented = false; onEdit($0) },
                             onDelete: onDelete,
                             onDismiss: { presented = false })
                .chromePopoverAppearance()
        }
    }
}

struct GitHubFilterMenu: View {
    let filters: [GitHubFilter]
    let selectedID: String
    let onSelect: (String) -> Void
    let onNew: () -> Void
    let onEdit: (GitHubFilter) -> Void
    let onDelete: (String) -> Void
    let onDismiss: () -> Void
    @State private var search = ""
    @State private var highlightedID: String?
    @FocusState private var searchFocused: Bool

    private var matches: [GitHubFilter] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return filters.filter { query.isEmpty || $0.name.localizedStandardContains(query) || $0.query.localizedStandardContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Filters").font(Theme.Font.title)
                Spacer()
                Text(filters.count, format: .number).font(Theme.Font.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find a filter", text: $search)
                    .textFieldStyle(.plain).focused($searchFocused)
                    .onSubmit { selectHighlighted() }
                    .onKeyPress(.downArrow) { moveHighlight(1); return .handled }
                    .onKeyPress(.upArrow) { moveHighlight(-1); return .handled }
            }
            .font(Theme.Font.body).padding(9)
            .background(Theme.Wash.faint, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .padding(.horizontal, 10).padding(.bottom, 8)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(matches) { filter in
                            GitHubFilterMenuRow(
                                filter: filter, selected: selectedID == filter.id, highlighted: highlightedID == filter.id,
                                canDelete: filters.count > 2,
                                onSelect: { onSelect(filter.id) }, onEdit: { onEdit(filter) }, onDelete: { onDelete(filter.id) }
                            )
                            .id(filter.id)
                            if filter.id == GitHubFilter.inboxID, filter.id != matches.last?.id {
                                Divider().padding(.horizontal, 4).padding(.vertical, 3)
                            }
                        }
                        if matches.isEmpty {
                            Text("No matching filters").font(Theme.Font.body).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 24)
                        }
                    }
                    .padding(.horizontal, 6).padding(.bottom, 6)
                }
                .frame(height: min(300, CGFloat(max(matches.count, 1)) * 50))
                .onChange(of: highlightedID) { _, id in
                    if let id {
                        proxy.scrollTo(id)
                    }
                }
            }
            Divider().padding(.horizontal, 10)
            Button(action: onNew) { Label("New Filter", systemImage: "plus") }
                .buttonStyle(.plain).font(Theme.Font.control)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .frame(width: 320)
        .onAppear { highlightedID = selectedID; searchFocused = true }
        .onChange(of: search) { highlightedID = matches.first?.id }
        .onExitCommand(perform: onDismiss)
    }

    private func moveHighlight(_ direction: Int) {
        guard !matches.isEmpty else { return }
        let current = matches.firstIndex { $0.id == highlightedID } ?? (direction > 0 ? -1 : matches.count)
        let index = min(max(0, current + direction), matches.count - 1)
        highlightedID = matches[index].id
    }

    private func selectHighlighted() {
        guard let id = highlightedID ?? matches.first?.id else { return }
        onSelect(id)
    }
}

private struct GitHubFilterMenuRow: View {
    let filter: GitHubFilter
    let selected: Bool
    let highlighted: Bool
    let canDelete: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    private var editable: Bool {
        filter.id != GitHubFilter.inboxID
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Button(action: onSelect) {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: filter.symbolName)
                        .foregroundStyle(.secondary).frame(width: 16).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: filter.name).font(Theme.Font.control).lineLimit(1)
                        Text(verbatim: filter.summary)
                            .font(editable ? .system(size: 10.5, design: .monospaced) : Theme.Font.caption)
                            .foregroundStyle(.secondary).lineLimit(editable ? 1 : 2).truncationMode(.tail)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent).padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            if editable {
                GitHubMoreMenu(extent: 20, help: "Filter options") { actions }
                    .padding(.leading, 4)
                    .opacity(highlighted || hovering ? 1 : 0)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(highlighted || hovering ? Theme.Wash.selection : .clear,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.control))
        .onHover { hovering = $0 }
        .contextMenu {
            if editable {
                actions
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        Button("Edit Filter…", action: onEdit)
        Button("Delete Filter", role: .destructive, action: onDelete).disabled(!canDelete)
    }
}

private extension GitHubFilter {
    private static let defaultQualifiers: Set<String> = ["is:open", "sort:updated-desc"]

    var summary: String {
        guard id != Self.inboxID else { return query }
        let distinct = query.split(separator: " ").filter { !Self.defaultQualifiers.contains(String($0)) }
        return distinct.isEmpty ? query : distinct.joined(separator: " ")
    }
}
