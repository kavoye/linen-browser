// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import UniformTypeIdentifiers

struct ProfileSettings: View {
    let coordinator: AppCoordinator

    @Environment(\.settingsRouter) private var router
    @State private var dropTarget: UUID?
    @State private var dragging: UUID?

    private enum Destination: Equatable {
        case profile(UUID)
        case newProfile
    }

    private var store: ProfileStore {
        coordinator.profiles
    }

    private var destination: Destination? {
        guard router.path.count == 1, let segment = router.path.first else { return nil }
        if segment == "new" {
            return .newProfile
        }
        guard let id = UUID(uuidString: segment), store.profiles.contains(where: { $0.id == id }) else { return nil }
        return .profile(id)
    }

    var body: some View {
        switch destination {
        case .newProfile:
            NewProfilePage(store: store) { router.back() }
        case .profile(let id):
            ProfileDetailPage(coordinator: coordinator, profileID: id) { router.back() }
        case nil:
            overview
        }
    }

    @ViewBuilder
    private var overview: some View {
        SettingsPageHeader(title: "Profiles")

        VStack(alignment: .leading, spacing: 7) {
            SettingsCard {
                ForEach(Array(store.profiles.enumerated()), id: \.element.id) { index, profile in
                    if index > 0 {
                        RowSeparator()
                    }
                    ProfileListRow(
                        profile: profile,
                        isCurrent: profile.id == store.current.id,
                        dragging: $dragging,
                        open: { router.open([profile.id.uuidString.lowercased()]) }
                    )
                    .settingsAnchor(
                        profile.id == store.current.id
                            ? "profiles.current" : "profiles.row.\(profile.id)"
                    )
                    .overlay(alignment: landing(above: profile) ? .top : .bottom) {
                        if dropTarget == profile.id {
                            Capsule()
                                .fill(Theme.accent)
                                .frame(height: 2)
                        }
                    }
                    .onDrop(
                        of: [.text],
                        delegate: ProfileDropDelegate(
                            profile: profile,
                            store: store,
                            target: $dropTarget,
                            dragging: $dragging
                        )
                    )
                }

                RowSeparator()
                AddRow(title: "Add profile…") { router.open(["new"]) }
                    .settingsAnchor("profiles.add")
            }
            .settingsAnchor("profiles.list")

            if store.hasMultiple {
                Text("Drag to reorder.")
                    .font(Theme.Font.label)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }
        }

        SettingsCard {
            DetailRow(title: "Open at launch") {
                SettingsMenu<UUID?>(
                    options: [
                        .init(value: nil, label: String(localized: "Last used profile"))
                    ] + store.profiles.map {
                        .init(value: $0.id, label: $0.name)
                    },
                    selection: Binding(
                        get: { store.launchProfileID },
                        set: { store.setLaunchProfile($0) }
                    )
                )
            }
        }
        .settingsAnchor("profiles.launch")
    }

    private func landing(above profile: Profile) -> Bool {
        guard let dragging,
              let from = store.profiles.firstIndex(where: { $0.id == dragging }),
              let to = store.profiles.firstIndex(where: { $0.id == profile.id })
        else { return true }
        return from > to
    }
}

// MARK: - One row in the list

private struct ProfilePageHeading<Trailing: View>: View {
    let profile: Profile
    let title: Text
    let caption: Text?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ProfileGlyph(profile: profile, size: 60)

            VStack(alignment: .leading, spacing: 6) {
                title
                    .font(.system(size: 21, weight: .semibold))

                if let caption {
                    caption
                        .font(Theme.Font.body)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            trailing
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProfileListRow: View {
    let profile: Profile
    let isCurrent: Bool
    @Binding var dragging: UUID?
    let open: () -> Void

    @State private var width: CGFloat = 0

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                ProfileGlyph(profile: profile, size: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: profile.name)
                        .font(Theme.Font.rowTitle)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if isCurrent {
                        Text("Current profile")
                            .font(Theme.Font.secondary)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                DrillInChevron()
            }
            .padding(.vertical, 9)
            .settingsRowTarget()
        }
        .buttonStyle(.plain)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onDrag {
            dragging = profile.id
            return NSItemProvider(object: profile.id.uuidString as NSString)
        } preview: {
            dragPreview
        }
    }

    private var dragPreview: some View {
        HStack(spacing: 10) {
            ProfileGlyph(profile: profile, size: 26)

            Text(verbatim: profile.name)
                .font(Theme.Font.rowTitle)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(width: max(width, 260), height: 44, alignment: .leading)
        .settingsSurface(
            in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        )
    }
}

private struct ProfileDropDelegate: DropDelegate {
    let profile: Profile
    let store: ProfileStore
    @Binding var target: UUID?
    @Binding var dragging: UUID?

    func validateDrop(info: DropInfo) -> Bool {
        dragging != nil && dragging != profile.id
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        target = profile.id
    }

    func dropExited(info: DropInfo) {
        target = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            target = nil
            dragging = nil
        }
        guard let dragging,
              let moved = store.profiles.first(where: { $0.id == dragging }),
              let destination = store.profiles.firstIndex(where: { $0.id == profile.id })
        else { return false }
        withAnimation(Theme.Motion.settle) {
            store.move(moved, to: destination)
        }
        return true
    }
}

// MARK: - A profile's own page

private struct ProfileDetailPage: View {
    let coordinator: AppCoordinator
    let profileID: UUID
    let onBack: () -> Void

    @State private var draft: String
    @State private var facts = ProfileFacts.empty
    @State private var deleting = false
    @State private var clearing = false
    @FocusState private var editing: Bool

    init(coordinator: AppCoordinator, profileID: UUID, onBack: @escaping () -> Void) {
        self.coordinator = coordinator
        self.profileID = profileID
        self.onBack = onBack
        let name = coordinator.profiles.profiles.first { $0.id == profileID }?.name
        _draft = State(initialValue: name ?? "")
    }

    private var store: ProfileStore {
        coordinator.profiles
    }

    private var profile: Profile? {
        store.profiles.first { $0.id == profileID }
    }

    private var isCurrent: Bool {
        profileID == store.current.id
    }

    var body: some View {
        if let profile {
            page(profile)
        }
    }

    @ViewBuilder
    private func page(_ profile: Profile) -> some View {
        SubPageHeader(backTitle: "Profiles", onBack: onBack) {
            if !profile.isOriginal {
                SettingsButton(title: "Delete profile…", isDestructive: true) { deleting = true }
                    .disabled(coordinator.isSwitchingProfile)
                    .confirmationDialog(
                        Text("Delete \"\(profile.name)\"?"),
                        isPresented: $deleting
                    ) {
                        Button("Delete profile", role: .destructive) {
                            Task { await delete(profile) }
                        }
                        Button("Cancel", role: .cancel) { deleting = false }
                    } message: {
                        Text("Deleting this profile removes its tabs, history, and sign-ins from this Mac. Downloads stay in the Downloads folder.")
                    }
            }
        }

        heading(profile)

        detailsSection(profile)
    }

    private func heading(_ profile: Profile) -> some View {
        ProfilePageHeading(
            profile: profile,
            title: Text(verbatim: profile.name),
            caption: isCurrent ? Text("Current profile") : nil
        ) {
            if !isCurrent {
                SettingsButton(title: "Switch to this profile") {
                    Task { await coordinator.switchProfile(to: profile) }
                }
                .disabled(coordinator.isSwitchingProfile)
            }
        }
        .task(id: profileID) {
            facts = await ProfileFacts.load(for: profile)
        }
        .onChange(of: editing) { _, isEditing in
            if !isEditing {
                commit(profile)
            }
        }
    }

    private func detailsSection(_ profile: Profile) -> some View {
        SettingsCard {
            DetailRow(title: "Name") {
                FieldChrome(isFocused: editing) {
                    TextField("", text: $draft)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.row)
                        .fieldPlaceholder("Name", isShowing: draft.isEmpty)
                        .focused($editing)
                        .frame(maxWidth: 190)
                        .onSubmit { commit(profile) }
                }
            }

            RowSeparator()

            ProfileLookEditor(
                symbol: Binding(
                    get: { profile.symbol },
                    set: { store.setAppearance(of: profile, symbol: $0, color: profile.color) }
                ),
                color: Binding(
                    get: { profile.color },
                    set: { store.setAppearance(of: profile, symbol: profile.symbol, color: $0) }
                )
            )

            RowSeparator()

            DetailRow(title: "Browsing history") {
                SettingsButton(title: "Clear…", isDestructive: true) { clearing = true }
                    .disabled(facts.pages == 0)
            }
        }
        .confirmationDialog(
            Text("Clear the history in \"\(profile.name)\"?"),
            isPresented: $clearing
        ) {
            Button("Clear History", role: .destructive) {
                Task { await clearHistory(profile) }
            }
            Button("Cancel", role: .cancel) { clearing = false }
        } message: {
            Text("This clears history and start page tiles for this profile. Other profiles keep their data.")
        }
    }

    private func commit(_ profile: Profile) {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            draft = profile.name
            return
        }
        store.rename(profile, to: trimmed)
    }

    private func clearHistory(_ profile: Profile) async {
        clearing = false
        if isCurrent {
            await BrowsingData.clear(
                [.history],
                range: .everything,
                history: coordinator.browser.history,
                agent: coordinator.conversationLog,
                context: coordinator.browser.context
            )
        } else {
            ProfileMaintenance.clearHistory(of: profile)
        }
        facts = await ProfileFacts.load(for: profile)
    }

    private func delete(_ profile: Profile) async {
        deleting = false
        onBack()
        if let application = coordinator.application {
            await application.prepareToRemove(profile: profile)
        } else if isCurrent, let fallback = store.profiles.first(where: { $0.id != profile.id }) {
            await coordinator.switchProfile(to: fallback)
        }
        await store.remove(profile)
    }
}

// MARK: - Making one

private struct NewProfilePage: View {
    let store: ProfileStore
    let onBack: () -> Void

    @State private var name = ""
    @State private var symbol = ProfileAppearance.defaultSymbol
    @State private var color = TabFolderColor.gray
    @FocusState private var naming: Bool

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        SubPageHeader(backTitle: "Profiles", onBack: onBack)

        ProfilePageHeading(
            profile: Profile(id: Profile.originalID, name: trimmed, symbol: symbol, color: color),
            title: Text("New Profile"),
            caption: Text("A new profile starts with no history, tabs, or sign-ins.")
        ) {
            EmptyView()
        }

        SettingsSection(title: "Name and appearance", symbol: "paintpalette") {
            DetailRow(title: "Name") {
                FieldChrome(isFocused: naming) {
                    TextField("", text: $name)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.row)
                        .fieldPlaceholder("Name", isShowing: name.isEmpty)
                        .focused($naming)
                        .frame(maxWidth: 190)
                        .onSubmit(add)
                }
            }

            RowSeparator()

            ProfileLookEditor(symbol: $symbol, color: $color)
        }

        SectionActions {
            SettingsButton(title: "Add Profile", isProminent: true, action: add)
                .disabled(trimmed.isEmpty)
        }
    }

    private func add() {
        guard !trimmed.isEmpty else { return }
        store.add(name: trimmed, symbol: symbol, color: color)
        onBack()
    }
}

// MARK: - Symbol and color

enum ProfileAppearance {
    static let defaultSymbol = "person"

    static let symbols = [
        "person", "person.2", "person.3", "figure.walk",
        "briefcase", "graduationcap", "book", "books.vertical",
        "house", "building.2", "building.columns", "storefront",
        "cart", "bag", "creditcard", "banknote",
        "flask", "atom", "hammer", "wrench.and.screwdriver",
        "paintbrush", "paintpalette", "camera", "photo",
        "gamecontroller", "music.note", "headphones", "film",
        "airplane", "car", "bicycle", "map",
        "leaf", "tree", "heart", "cross.case",
        "bolt", "flame", "drop", "sun.max",
        "moon", "cloud", "globe", "network",
        "terminal", "chart.bar", "chart.line.uptrend.xyaxis", "cube",
        "envelope", "bell", "calendar", "clock",
        "folder", "tag", "key", "lock",
        "gift", "cup.and.saucer", "fork.knife", "dumbbell",
        "star", "sparkles", "crown", "puzzlepiece",
    ]

    static let swatchSize: CGFloat = 28
    static let symbolSize: CGFloat = 30
}

private struct ProfileLookEditor: View {
    @Binding var symbol: String
    @Binding var color: TabFolderColor

    private static func columns(of size: CGFloat, spacing: CGFloat) -> [GridItem] {
        [GridItem(.adaptive(minimum: size, maximum: size), spacing: spacing, alignment: .leading)]
    }

    var body: some View {
        DetailRow(title: "Color", layout: .stacked) {
            LazyVGrid(
                columns: Self.columns(of: ProfileAppearance.swatchSize, spacing: 8),
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(TabFolderColor.allCases) { swatch in
                    ProfileColorChoice(
                        color: swatch,
                        isSelected: swatch == color
                    ) {
                        color = swatch
                    }
                }
            }
        }

        RowSeparator()

        DetailRow(title: "Symbol", layout: .stacked) {
            LazyVGrid(
                columns: Self.columns(of: ProfileAppearance.symbolSize, spacing: 6),
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(ProfileAppearance.symbols, id: \.self) { candidate in
                    ProfileSymbolChoice(
                        symbol: candidate,
                        isSelected: candidate == symbol,
                        tint: color.tint
                    ) {
                        symbol = candidate
                    }
                }
            }
        }
    }
}

private struct ProfileChoiceBackground<S: Shape>: ViewModifier {
    let isSelected: Bool
    let tint: Color
    let shape: S

    private var fill: Color {
        isSelected ? tint.opacity(0.18) : .clear
    }

    func body(content: Content) -> some View {
        content
            .background { shape.fill(fill) }
            .contentShape(shape)
    }
}

private extension View {
    func profileChoiceBackground<S: Shape>(
        isSelected: Bool,
        tint: Color,
        in shape: S
    ) -> some View {
        modifier(ProfileChoiceBackground(
            isSelected: isSelected,
            tint: tint,
            shape: shape
        ))
    }
}

private struct ProfileColorChoice: View {
    let color: TabFolderColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color.tint.opacity(0.85))
                .frame(width: 20, height: 20)
                .padding(4)
                .profileChoiceBackground(
                    isSelected: isSelected,
                    tint: color.tint,
                    in: Circle()
                )
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(Text(color.title))
    }
}

private struct ProfileSymbolChoice: View {
    let symbol: String
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
                .frame(width: 30, height: 30)
                .profileChoiceBackground(
                    isSelected: isSelected,
                    tint: tint,
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
    }
}
