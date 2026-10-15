// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct SpaceEditor: View {
    let coordinator: AppCoordinator
    let target: SpaceEditorTarget

    @State private var name = ""
    @State private var symbol = Space.defaultSymbol
    @State private var color = TabFolderColor.blue
    @State private var isSeparate = false
    @State private var sharedProfileID = Profile.originalID
    @State private var isDeleting = false
    @State private var isChoosingIcon = false
    @State private var isHoveringIcon = false
    @State private var hasLoaded = false
    @FocusState private var isNaming: Bool

    private var store: SpaceStore {
        coordinator.spaceStore
    }

    private var editing: Space? {
        guard case .edit(let id) = target else { return nil }
        return store.space(id: id)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sharedName: String {
        sharingChoices.first { $0.profileID == sharedProfileID }?.name ?? ""
    }

    private var sharingChoices: [Space] {
        var seen: Set<UUID> = []
        return store.spaces.filter { seen.insert($0.profileID).inserted }
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView {
                    GlassEffectContainer(spacing: 0) {
                        VStack(spacing: 16) {
                            iconTile
                            nameField
                            dataChoice
                                .padding(.top, 8)
                            if let editing, store.canRemove(editing) {
                                Button("Delete Space…", role: .destructive) {
                                    isDeleting = true
                                }
                                .buttonStyle(.plain)
                                .font(Theme.Font.control)
                                .foregroundStyle(.red)
                                .padding(.top, 2)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 40)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollIndicators(.never)
                .scrollBounceBehavior(.basedOnSize)
            }

            footer
        }
        .padding(.top, 24)
        .onAppear(perform: load)
        .onChange(of: name) { _, _ in saveEdits() }
        .onChange(of: symbol) { _, _ in saveEdits() }
        .onExitCommand(perform: close)
        .alert(deleteTitle, isPresented: $isDeleting) {
            Button("Delete", role: .destructive) {
                guard let editing else { return }
                let isLast = store.ownsLastSpace(of: editing)
                Task { await coordinator.removeSpace(editing, confirmedAsLast: isLast) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            deleteMessage
        }
    }

    private var iconTile: some View {
        Button {
            isChoosingIcon.toggle()
        } label: {
            Image(systemName: symbol)
                .symbolVariant(.fill)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.primary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 72, height: 72)
                .scaleEffect(isHoveringIcon ? 1.08 : 1)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHoveringIcon = $0 }
        .animation(Theme.Motion.quick, value: isHoveringIcon)
        .help(String(localized: "Choose Icon"))
        .popover(isPresented: $isChoosingIcon, arrowEdge: .bottom) {
            symbolGrid
        }
    }

    private var nameField: some View {
        TextField(text: $name, prompt: Text(verbatim: "")) {
            Text("Name")
        }
        .textFieldStyle(.plain)
        .font(.system(size: 15, weight: .semibold))
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .focused($isNaming)
        .overlay {
            if name.isEmpty {
                Text("Space Name")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .onSubmit {
            if editing == nil {
                create()
            }
        }
    }

    private var symbolGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 4), count: 8), spacing: 4) {
            ForEach(SpaceAppearance.symbols, id: \.self) { candidate in
                SpaceChoice(isSelected: candidate == symbol) {
                    symbol = candidate
                    isChoosingIcon = false
                } label: {
                    Image(systemName: candidate)
                        .symbolVariant(.fill)
                        .font(.system(size: 13))
                        .foregroundStyle(candidate == symbol ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                }
            }
        }
        .padding(10)
    }

    @ViewBuilder
    private var dataChoice: some View {
        if let editing {
            Text(sharingSummary(for: editing))
                .font(Theme.Font.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sign-ins and data")
                    .font(Theme.Font.label)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                SpaceDataOption(symbol: "person.2.fill", title: "Shared", isSelected: !isSeparate) {
                    isSeparate = false
                } detail: {
                    sharedDetail
                }

                SpaceDataOption(symbol: "lock.fill", title: "Separate", isSelected: isSeparate) {
                    isSeparate = true
                } detail: {
                    Text("A separate space has its own cookies, passwords, history and settings.")
                }
            }
        }
    }

    @ViewBuilder
    private var sharedDetail: some View {
        if sharingChoices.count > 1 {
            HStack(spacing: 4) {
                Text("Same as")
                Menu {
                    ForEach(sharingChoices) { space in
                        Button {
                            sharedProfileID = space.profileID
                            isSeparate = false
                        } label: {
                            Text(verbatim: space.name)
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(verbatim: sharedName)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        } else {
            Text("Same as \(sharedName)")
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if editing == nil {
                Button(action: close) {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)

                Button(action: create) {
                    Text("Create Space")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            } else {
                Button(action: close) {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.extraLarge)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    private var deleteTitle: Text {
        Text("Delete “\(editing?.name ?? name)”?")
    }

    @ViewBuilder
    private var deleteMessage: some View {
        if let editing, store.ownsLastSpace(of: editing) {
            Text("Its tabs close, and its sign-ins, history and other data are deleted. You can’t undo this.")
        } else {
            Text("Its tabs close. You can’t undo this.")
        }
    }

    private func sharingSummary(for space: Space) -> String {
        let others = store.spaces(for: space.profileID).filter { $0.id != space.id }.map(\.name)
        guard !others.isEmpty else {
            return String(localized: "This space has its own sign-ins and data.")
        }
        let shown = others.count > 3
            ? Array(others.prefix(2)) + [String(localized: "\(others.count - 2) more")]
            : others
        let names = shown.formatted(.list(type: .and))
        return String(localized: "Shares sign-ins and data with \(names).")
    }

    private func load() {
        guard !hasLoaded else { return }
        hasLoaded = true
        if let editing {
            name = editing.name
            symbol = editing.symbol
            color = editing.color
            return
        }
        let used = Set(store.spaces.map(\.color))
        color = TabFolderColor.allCases.first { $0 != .gray && !used.contains($0) } ?? .blue
        sharedProfileID = coordinator.currentSpace?.profileID ?? coordinator.profiles.current.id
        isNaming = true
    }

    private func saveEdits() {
        guard hasLoaded, var space = editing, !trimmedName.isEmpty else { return }
        space.name = trimmedName
        space.symbol = symbol
        coordinator.updateSpace(space)
    }

    private func create() {
        guard editing == nil, !trimmedName.isEmpty else { return }
        let shared = isSeparate ? nil : store.spaces.first { $0.profileID == sharedProfileID }
        isNaming = false
        coordinator.createSpace(name: trimmedName, symbol: symbol, color: color, sharingWith: shared)
    }

    private func close() {
        coordinator.spaceSlider.closeEditor()
    }
}

private struct SpaceDataOption<Detail: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let isSelected: Bool
    var action: (() -> Void)?
    @ViewBuilder let detail: Detail

    @State private var confirms = false

    private var glass: Glass {
        isSelected ? .regular.tint(Theme.accent.opacity(0.28)).interactive() : .regular.interactive()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: confirms ? "checkmark" : symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Font.row)
                    .foregroundStyle(.primary)
                detail
                    .font(Theme.Font.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .glassEffect(glass, in: .rect(cornerRadius: 14))
        .contentShape(.rect(cornerRadius: 14))
        .onTapGesture {
            guard let action, !isSelected else { return }
            action()
        }
        .onChange(of: isSelected) { _, selected in
            guard selected else { return }
            withAnimation(.smooth(duration: 0.25)) { confirms = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(900))
                withAnimation(.smooth(duration: 0.25)) { confirms = false }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

private struct SpaceChoice<Label: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) {
            label
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? Theme.accent.opacity(0.18) : .clear)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
