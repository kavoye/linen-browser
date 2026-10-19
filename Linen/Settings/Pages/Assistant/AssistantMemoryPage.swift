// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct AssistantMemoryPage: View {
    let memory: AssistantMemory
    let onBack: () -> Void

    @State private var isEnabled = AssistantMemory.isEnabled
    @State private var query = ""
    @State private var editingID: UUID?
    @State private var draft = ""
    @State private var confirmingForgetAll = false

    @MainActor
    static func summary(for memory: AssistantMemory) -> LocalizedStringResource {
        guard AssistantMemory.isEnabled else { return "Off" }
        return memory.facts.isEmpty ? "None" : "\(memory.facts.count) things"
    }

    private var shown: [AssistantMemory.Fact] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return memory.facts }
        return memory.facts.filter {
            $0.subject.localizedCaseInsensitiveContains(needle) || $0.value.localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        SubPageHeader(backTitle: "Assistant", onBack: onBack)

        SettingsPageHeader(
            title: "Memory",
            caption: "What the assistant remembers about you. It saves your answers and what you ask it to remember. It never saves page content, passwords, or payment details."
        )

        SettingsCard {
            DetailRow(
                title: "Remember things about me",
                caption: "When this is off, the assistant can’t save or recall anything."
            ) {
                SettingsToggle($isEnabled)
            }
        }
        .onChange(of: isEnabled) { _, enabled in
            AssistantMemory.isEnabled = enabled
        }
        .padding(.top, 6)

        if memory.facts.count > 5 {
            SearchFieldChrome {
                TextField("", text: $query)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.secondary)
                    .fieldPlaceholder("Search memory", isShowing: query.isEmpty)
            }
            .padding(.top, 12)
        }

        SettingsCard {
            if memory.facts.isEmpty {
                SettingsEmptyState(
                    symbol: "square.and.pencil",
                    title: "Nothing remembered",
                    caption: "Things appear here when you answer the assistant or ask it to remember something."
                )
            } else if shown.isEmpty {
                SettingsEmptyState(symbol: "magnifyingglass", title: "No matches", caption: "Try a different word.")
            } else {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, fact in
                    if index > 0 {
                        RowSeparator()
                    }
                    row(for: fact)
                }
            }
        }
        .padding(.top, 6)

        if !memory.facts.isEmpty {
            SectionActions {
                SettingsButton(title: "Forget All…", isDestructive: true, symbol: "trash") {
                    confirmingForgetAll = true
                }
            }
            .confirmationDialog("Forget everything the assistant remembers?", isPresented: $confirmingForgetAll) {
                Button("Forget All", role: .destructive) { memory.forgetAll() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The assistant will ask again when it needs these details.")
            }
        }
    }

    @ViewBuilder private func row(for fact: AssistantMemory.Fact) -> some View {
        if editingID == fact.id {
            DetailRow(verbatimTitle: Self.title(for: fact), layout: .stacked) {
                HStack(spacing: 8) {
                    FieldChrome(isFocused: true) {
                        TextField("", text: $draft)
                            .textFieldStyle(.plain)
                            .onSubmit { save(fact) }
                    }
                    SettingsButton(title: "Save") { save(fact) }
                    SettingsButton(title: "Cancel") { editingID = nil }
                }
            }
        } else {
            DetailRow(verbatimTitle: Self.title(for: fact), verbatimCaption: fact.value + " · " + Self.origin(of: fact)) {
                HStack(spacing: 8) {
                    SettingsButton(title: "Edit") {
                        draft = fact.value
                        editingID = fact.id
                    }
                    SettingsButton(title: "Forget", isDestructive: true) {
                        memory.forget(fact.id)
                    }
                }
            }
        }
    }

    private func save(_ fact: AssistantMemory.Fact) {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            memory.update(fact, value: value)
        }
        editingID = nil
    }

    private static func title(for fact: AssistantMemory.Fact) -> String {
        fact.subject.prefix(1).uppercased() + fact.subject.dropFirst()
    }

    private static func origin(of fact: AssistantMemory.Fact) -> String {
        let day = fact.savedAt.formatted(date: .abbreviated, time: .omitted)
        switch fact.source {
        case .answer:
            return String(localized: "Saved \(day) from your answer")
        case .message:
            return String(localized: "Saved \(day) from your message")
        case .model:
            return String(localized: "Saved \(day) by the assistant")
        }
    }
}
