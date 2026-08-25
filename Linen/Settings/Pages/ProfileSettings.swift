// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import UniformTypeIdentifiers

struct ProfileSettings: View {
    let coordinator: AppCoordinator

    @State private var destination: Destination?
    @State private var dropTarget: UUID?
    @State private var dragging: UUID?

    private enum Destination: Equatable {
        case profile(UUID)
        case newProfile
    }

    private var store: ProfileStore {
        coordinator.profiles
    }

    private var listed: [Profile] {
        store.profiles.filter { $0.id != store.current.id }
    }

    var body: some View {
        switch destination {
        case .newProfile:
            NewProfilePage(store: store) { destination = nil }
        case .profile(let id):
            ProfileDetailPage(coordinator: coordinator, profileID: id) { destination = nil }
        case nil:
            overview
        }
    }

    @ViewBuilder
    private var overview: some View {
        SettingsPageHeader(
            title: "Profiles",
            caption: "Each profile keeps its own sign-ins, history, tabs, and extensions."
        )

        SettingsSection(title: "Current profile", symbol: "person.crop.circle") {
            ProfileHeroCard(coordinator: coordinator) {
                destination = .profile(store.current.id)
            }
        }
        .settingsAnchor("profiles.current")

        SettingsSection(title: "Other profiles", symbol: "person.2", footnote: reorderHint) {
            ForEach(Array(listed.enumerated()), id: \.element.id) { index, profile in
                if index > 0 {
                    RowSeparator()
                }
                ProfileListRow(
                    coordinator: coordinator,
                    profile: profile,
                    dragging: $dragging,
                    open: { destination = .profile(profile.id) }
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

            if !listed.isEmpty {
                RowSeparator()
            }

            AddRow(title: "Add Profile…") { destination = .newProfile }
                .settingsAnchor("profiles.add")
        }
        .settingsAnchor("profiles.list")

        SettingsSection(title: "Linen opens in", symbol: "power") {
            OptionList(
                options: [
                    OptionList<Bool>.Option(
                        value: false,
                        label: "The last profile used",
                        caption: "Currently \(store.profileToReturnTo.name)."
                    ),
                    OptionList<Bool>.Option(
                        value: true,
                        label: "A specific profile",
                        caption: "Linen opens in the same profile every time."
                    ),
                ],
                selection: store.launchProfileID != nil,
                onSelect: { pinned in
                    store.setLaunchProfile(pinned ? store.profileToReturnTo.id : nil)
                }
            )

            if store.launchProfileID != nil {
                RowSeparator()

                DetailRow(title: "Profile") {
                    SettingsMenu(
                        options: store.profiles.map {
                            SettingsMenu<UUID>.Option(value: $0.id, label: $0.name)
                        },
                        selection: Binding(
                            get: { store.launchProfileID ?? store.profileToReturnTo.id },
                            set: { store.setLaunchProfile($0) }
                        )
                    )
                }
            }
        }
        .settingsAnchor("profiles.launch")
    }

    private var reorderHint: LocalizedStringResource? {
        guard store.hasMultiple else { return nil }
        return "Drag a profile to change the order."
    }

    private func landing(above profile: Profile) -> Bool {
        guard let dragging,
              let from = store.profiles.firstIndex(where: { $0.id == dragging }),
              let to = store.profiles.firstIndex(where: { $0.id == profile.id })
        else { return true }
        return from > to
    }
}

// MARK: - The profile you're in

private struct ProfileHeroCard: View {
    let coordinator: AppCoordinator
    let edit: () -> Void

    @State private var facts = ProfileFacts.empty
    @State private var websites: Int?

    private var profile: Profile {
        coordinator.profiles.current
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                ProfileGlyph(profile: profile, size: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: profile.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if profile.isPrivate {
                        Text("Nothing in this profile is saved.")
                            .font(Theme.Font.secondary)
                            .foregroundStyle(.secondary)
                    } else if let started = facts.firstVisit {
                        Text("In use since \(started.formatted(.dateTime.month(.wide).day()))")
                            .font(Theme.Font.secondary)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                if !profile.isPrivate {
                    SettingsButton(title: "Edit…", action: edit)
                }
            }
            .padding(.vertical, SettingsMetrics.rowPaddingV)

            if !profile.isPrivate {
                RowSeparator()

                StatStrip(figures: [
                    StatStrip.Figure(
                        value: coordinator.browser.tabs.count.formatted(),
                        label: "Tabs"
                    ),
                    StatStrip.Figure(value: facts.pages.formatted(), label: "Pages of history"),
                    StatStrip.Figure(
                        value: coordinator.extensions.installed.count.formatted(),
                        label: "Extensions"
                    ),
                    StatStrip.Figure(
                        value: websites.map { $0.formatted() } ?? "—",
                        label: "Websites with data"
                    ),
                ])
            }
        }
        .task(id: profile.id) {
            facts = await ProfileFacts.load(for: profile)
            websites = profile.isPrivate ? nil : await BrowsingData.siteCount()
        }
    }
}

// MARK: - One row in the list

private struct ProfileListRow: View {
    let coordinator: AppCoordinator
    let profile: Profile
    @Binding var dragging: UUID?
    let open: () -> Void

    @State private var facts = ProfileFacts.empty
    @State private var hovering = false
    @State private var width: CGFloat = 0

    private var store: ProfileStore {
        coordinator.profiles
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                ProfileGlyph(profile: profile, size: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: profile.name)
                        .font(Theme.Font.rowTitle)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(verbatim: summary)
                        .font(Theme.Font.secondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                SettingsButton(title: "Open") {
                    Task { await coordinator.switchProfile(to: profile) }
                }
                .disabled(coordinator.isSwitchingProfile)
                .opacity(hovering ? 1 : 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 9)
            .settingsRowHover(isActive: hovering, tint: profile.color.tint)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onDrag {
            dragging = profile.id
            return NSItemProvider(object: profile.id.uuidString as NSString)
        } preview: {
            dragPreview
        }
        .task(id: profile.id) {
            facts = await ProfileFacts.load(for: profile)
        }
    }

    private var summary: String {
        let used = store.lastUsed[profile.id]
        guard facts.tabs > 0 || used != nil else {
            return String(localized: ProfileSummary.neverOpened)
        }
        var parts = [ProfileSummary.tabs(facts.tabs)]
        if let used {
            parts.append(ProfileSummary.lastUsed(used))
        }
        return parts.joined(separator: " · ")
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
        SubPageHeader(backTitle: "Profiles", onBack: onBack)

        heading(profile)

        lookSection(profile)

        contentsSection(profile)

        SettingsSection(
            title: "Kept separate from other profiles",
            symbol: "rectangle.split.2x1",
            footnote: "Appearance, downloads, and keyboard shortcuts are shared by every profile."
        ) {
            ChipList(items: ProfileSummary.separated)
        }

        if !profile.isOriginal {
            SectionActions {
                SettingsButton(title: "Delete Profile…", isDestructive: true) { deleting = true }
                    .disabled(coordinator.isSwitchingProfile)
            }
            .confirmationDialog(
                Text("Delete “\(profile.name)”?"),
                isPresented: $deleting
            ) {
                Button("Delete Profile", role: .destructive) {
                    Task { await delete(profile) }
                }
                Button("Cancel", role: .cancel) { deleting = false }
            } message: {
                Text("Its \(facts.pages) pages of history, tabs, and sign-ins are removed from this Mac. Downloaded files stay in the Downloads folder.")
            }
        }
    }

    private func heading(_ profile: Profile) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ProfileGlyph(profile: profile, size: 60)

            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: profile.name)
                    .font(.system(size: 21, weight: .semibold))

                Text(verbatim: header(for: profile))
                    .font(Theme.Font.body)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if !isCurrent {
                SettingsButton(title: "Open Profile") {
                    Task { await coordinator.switchProfile(to: profile) }
                }
                .disabled(coordinator.isSwitchingProfile)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: profileID) {
            facts = await ProfileFacts.load(for: profile)
        }
        .onChange(of: editing) { _, isEditing in
            if !isEditing {
                commit(profile)
            }
        }
    }

    private func lookSection(_ profile: Profile) -> some View {
        SettingsSection(title: "Name and appearance", symbol: "paintpalette") {
            DetailRow(title: "Name") {
                FieldChrome(isFocused: editing) {
                    TextField("Name", text: $draft)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.row)
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
        }
    }

    private func contentsSection(_ profile: Profile) -> some View {
        SettingsSection(title: "Contents", symbol: "tray.full") {
            StatusRow(
                tint: Color(nsColor: .systemGray),
                symbol: "rectangle.stack",
                title: "Tabs",
                verbatimCaption: ProfileSummary.tabsAndFolders(
                    tabs: isCurrent ? coordinator.browser.tabs.count : facts.tabs,
                    folders: facts.folders
                )
            ) {
                EmptyView()
            }

            RowSeparator()

            StatusRow(
                tint: SettingsCategory.privacy.tint,
                symbol: "clock",
                title: "History",
                verbatimCaption: ProfileSummary.history(pages: facts.pages, since: facts.firstVisit)
            ) {
                if facts.pages > 0 {
                    SettingsButton(title: "Clear…", isDestructive: true) { clearing = true }
                }
            }

            RowSeparator()

            StatusRow(
                tint: SettingsCategory.extensions.tint,
                symbol: "puzzlepiece.extension",
                title: "Extensions",
                verbatimCaption: ProfileSummary.extensions(facts.extensions)
            ) {
                if isCurrent, facts.extensions > 0 {
                    SettingsButton(title: "Show") { coordinator.openSettings(.extensions) }
                }
            }

            RowSeparator()

            StatusRow(
                tint: SettingsCategory.websites.tint,
                symbol: "hand.raised",
                title: "Website permissions",
                verbatimCaption: ProfileSummary.permissions(facts.permissionSites)
            ) {
                if isCurrent, facts.permissionSites > 0 {
                    SettingsButton(title: "Show") { coordinator.openSettings(.websites) }
                }
            }

            RowSeparator()

            StatusRow(
                tint: Color(nsColor: .systemGray),
                symbol: "internaldrive",
                title: "Size on disk",
                verbatimCaption: ProfileSummary.size(facts.bytes)
            ) {
                EmptyView()
            }
        }
        .confirmationDialog(
            Text("Clear the history in “\(profile.name)”?"),
            isPresented: $clearing
        ) {
            Button("Clear History", role: .destructive) {
                Task { await clearHistory(profile) }
            }
            Button("Cancel", role: .cancel) { clearing = false }
        } message: {
            Text("Its \(facts.pages) pages of history are removed, along with the start page tiles. Other profiles are not affected.")
        }
    }

    private func header(for profile: Profile) -> String {
        let tabs = isCurrent ? coordinator.browser.tabs.count : facts.tabs
        let used = isCurrent ? nil : store.lastUsed[profile.id]
        guard tabs > 0 || facts.bytes > 0 || used != nil else {
            return String(localized: ProfileSummary.neverOpened)
        }
        var parts = [ProfileSummary.tabs(tabs)]
        if facts.bytes > 0 {
            parts.append(ProfileSummary.size(facts.bytes))
        }
        if let used {
            parts.append(ProfileSummary.lastUsed(used))
        }
        return parts.joined(separator: " · ")
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
                agent: coordinator.conversationLog
            )
        } else {
            ProfileMaintenance.clearHistory(of: profile)
        }
        facts = await ProfileFacts.load(for: profile)
    }

    private func delete(_ profile: Profile) async {
        deleting = false
        onBack()
        if isCurrent, let fallback = store.profiles.first(where: { $0.id != profile.id }) {
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

        HStack(alignment: .center, spacing: 14) {
            ProfileGlyph(
                profile: Profile(id: Profile.originalID, name: trimmed, symbol: symbol, color: color),
                size: 60
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("New Profile")
                    .font(.system(size: 21, weight: .semibold))

                Text("A new profile starts with no history, tabs, or sign-ins.")
                    .font(Theme.Font.body)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        SettingsSection(title: "Name and appearance", symbol: "paintpalette") {
            DetailRow(title: "Name") {
                FieldChrome(isFocused: naming) {
                    TextField("Name", text: $name)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.row)
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
                    in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }
}
