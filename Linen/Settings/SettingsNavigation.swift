// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case appearance
    case search
    case provider
    case profiles
    case privacy
    case websites
    case downloads
    case extensions
    case advanced
    case experiments
    case about

    var id: String {
        rawValue
    }

    var title: LocalizedStringResource {
        switch self {
        case .general:
            "General"
        case .search:
            "Search"
        case .appearance:
            "Appearance"
        case .provider:
            "Assistant"
        case .profiles:
            "Profiles"
        case .privacy:
            "Privacy"
        case .websites:
            "Websites"
        case .downloads:
            "Downloads"
        case .extensions:
            "Extensions"
        case .advanced:
            "Advanced"
        case .experiments:
            "Experiments"
        case .about:
            "About"
        }
    }

    var symbol: String {
        switch self {
        case .general:
            "gearshape"
        case .search:
            "magnifyingglass"
        case .appearance:
            "circle.lefthalf.filled"
        case .provider:
            "sparkles"
        case .profiles:
            "person.2"
        case .privacy:
            "hand.raised"
        case .websites:
            "globe"
        case .downloads:
            "arrow.down"
        case .extensions:
            "puzzlepiece.extension"
        case .advanced:
            "wrench.and.screwdriver"
        case .experiments:
            "flask"
        case .about:
            "info.circle"
        }
    }

    var group: SettingsGroup? {
        switch self {
        case .general, .search, .appearance:
            .setup
        case .provider:
            .intelligence
        case .privacy, .websites, .downloads, .extensions:
            .browsing
        case .advanced, .experiments, .about:
            .system
        case .profiles:
            nil
        }
    }

    var tint: Color {
        switch self {
        case .general:
            Color(nsColor: .systemGray)
        case .search:
            Color(nsColor: .systemBrown)
        case .appearance:
            Color(nsColor: .systemIndigo)
        case .provider:
            Color(nsColor: .systemPurple)
        case .profiles:
            Color(nsColor: .systemCyan)
        case .privacy:
            Color(nsColor: .systemBlue)
        case .websites:
            Color(nsColor: .systemTeal)
        case .downloads:
            Color(nsColor: .systemGreen)
        case .extensions:
            Color(nsColor: .systemOrange)
        case .advanced, .experiments, .about:
            Color(nsColor: .systemGray)
        }
    }

    var keywords: [String] {
        switch self {
        case .general:
            ["startup", "home", "homepage", "new tab", "default browser", "launch", "import"]
        case .search:
            ["search", "engine", "google", "duckduckgo", "bing", "kagi", "suggestions",
             "omnibox", "address bar", "ask", "query",
             ]
        case .appearance:
            ["theme", "dark", "light", "loom", "color", "zoom", "sidebar", "font size"]
        case .provider:
            ["model", "api key", "openai", "anthropic", "ollama", "endpoint", "reasoning", "llm", "engine",
             "intelligence", "provider", "voice", "speech", "spoken", "push to talk", "microphone",
             "dictation", "shortcut",
             ]
        case .profiles:
            ["profile", "profiles", "work", "personal", "separate", "account", "switch", "identity"]
        case .privacy:
            ["cookies", "cache", "clear", "history", "storage", "tracking", "site data"]
        case .websites:
            ["javascript", "popups", "autoplay", "permissions", "media", "content"]
        case .downloads:
            ["files", "save", "folder", "downloads"]
        case .extensions:
            ["chrome", "web store", "add-ons", "plugins"]
        case .advanced:
            ["user agent", "developer", "inspector", "devtools", "reset", "certificate", "proxy"]
        case .experiments:
            ["experiment", "experiments", "experimental", "flag", "flags", "feature", "preview",
             "video", "player", "media",
             ]
        case .about:
            ["version", "update", "release", "build", "credits", "licence", "license", "open source"]
        }
    }

    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return true }
        if String(localized: title).lowercased().contains(needle) {
            return true
        }
        if let group, String(localized: group.title).lowercased().contains(needle) {
            return true
        }
        return keywords.contains { $0.contains(needle) }
    }
}

enum SettingsGroup: String, CaseIterable, Identifiable {
    case setup
    case intelligence
    case browsing
    case system

    var id: String {
        rawValue
    }

    var title: LocalizedStringResource {
        switch self {
        case .setup:
            "Browser"
        case .intelligence:
            "Assistant"
        case .browsing:
            "Browsing"
        case .system:
            "System"
        }
    }

    var header: LocalizedStringResource? {
        switch self {
        case .setup, .intelligence:
            nil
        case .browsing, .system:
            title
        }
    }

    var categories: [SettingsCategory] {
        SettingsCategory.allCases.filter { $0.group == self }
    }
}

struct SettingsNavigator: View {
    @Binding var selection: SettingsCategory
    @Binding var query: String
    var profileName: String
    var profileSymbol: String
    var profileTint: Color
    var badges: [SettingsCategory: String] = [:]
    var showsNames = true
    var onOpen: (SettingsEntry) -> Void = { _ in }

    @FocusState private var searchFocused: Bool

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var results: [SettingsEntry] {
        SettingsIndex.search(query)
    }

    private var matchingPages: [SettingsCategory] {
        SettingsCategory.allCases.filter { $0.matches(query) }
    }

    private var groups: [(group: SettingsGroup, categories: [SettingsCategory])] {
        SettingsGroup.allCases.compactMap { group in
            let categories = group.categories
            return categories.isEmpty ? nil : (group, categories)
        }
    }

    var body: some View {
        if showsNames {
            named
        } else {
            iconsOnly
        }
    }

    private var iconsOnly: some View {
        ScrollView {
            VStack(spacing: 4) {
                NavigatorIcon(
                    symbol: profileSymbol,
                    tint: profileTint,
                    title: profileName,
                    isSelected: selection == .profiles
                ) {
                    selection = .profiles
                }

                Divider()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)

                ForEach(SettingsCategory.allCases.filter { $0 != .profiles }) { category in
                    NavigatorIcon(
                        symbol: category.symbol,
                        tint: category.tint,
                        title: String(localized: category.title),
                        isSelected: category == selection
                    ) {
                        selection = category
                    }
                }
            }
            .padding(.vertical, 10)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var named: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigatorProfileBlock(
                name: profileName,
                symbol: profileSymbol,
                tint: profileTint,
                isSelected: selection == .profiles
            ) {
                selection = .profiles
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)

            search
                .padding(.horizontal, 10)
                .padding(.top, 12)
                .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if isSearching {
                        resultsList
                    } else {
                        categoryList
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 14)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: - Un-searched

    private var categoryList: some View {
        ForEach(groups, id: \.group.id) { entry in
            VStack(alignment: .leading, spacing: 1) {
                if let title = entry.group.header {
                    header(title)
                }

                ForEach(entry.categories) { category in
                    NavigatorRow(
                        category: category,
                        badge: badges[category],
                        isSelected: category == selection
                    ) {
                        selection = category
                    }
                }
            }
        }
    }

    // MARK: - Searched

    @ViewBuilder
    private var resultsList: some View {
        if results.isEmpty && matchingPages.isEmpty {
            Text("Nothing matches.")
                .font(Theme.Font.secondary)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.top, 4)
        }

        if !results.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                header("Settings")

                ForEach(results) { entry in
                    ResultRow(entry: entry) { onOpen(entry) }
                }
            }
        }

        if !matchingPages.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                header("Pages")

                ForEach(matchingPages) { category in
                    NavigatorRow(
                        category: category,
                        badge: badges[category],
                        isSelected: category == selection
                    ) {
                        selection = category
                    }
                }
            }
        }
    }

    private func header(_ title: LocalizedStringResource) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.4)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 9)
            .padding(.bottom, 6)
    }

    private var search: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)

            TextField("Search settings", text: $query)
                .textFieldStyle(.plain)
                .font(Theme.Font.secondary)
                .focused($searchFocused)
                .onSubmit {
                    if let first = results.first {
                        onOpen(first)
                    } else if let page = matchingPages.first {
                        selection = page
                    }
                }

            if !query.isEmpty {
                ChromeIcon(symbol: "xmark", size: 9, extent: 18, help: String(localized: "Clear Search")) {
                    query = ""
                    searchFocused = true
                }
            }
        }
        .padding(.horizontal, 9)
        .frame(height: SettingsMetrics.controlHeight)
        .glassSurface(
            in: RoundedRectangle(cornerRadius: SettingsMetrics.controlRadius, style: .continuous)
        )
    }
}

private struct CategoryTile: View {
    let symbol: String
    let tint: Color

    static let size: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: Self.size * 0.28, style: .continuous)
            .fill(tint)
            .frame(width: Self.size, height: Self.size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

private struct NavigatorIcon: View {
    let symbol: String
    let tint: Color
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            CategoryTile(symbol: symbol, tint: tint)
                .frame(width: 32, height: 32)
                .selectionBackground(
                    isSelected: isSelected,
                    isHovering: hovering,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.hover, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .help(Text(verbatim: title))
        .accessibilityLabel(Text(verbatim: title))
    }
}

private struct NavigatorRow: View {
    let category: SettingsCategory
    let badge: String?
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                CategoryTile(symbol: category.symbol, tint: category.tint)

                Text(category.title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)

                Spacer(minLength: 6)

                if let badge {
                    Text(verbatim: badge)
                        .font(Theme.Font.micro)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 7)
            .frame(height: 32)
            .selectionBackground(
                isSelected: isSelected,
                isHovering: hovering,
                in: RoundedRectangle(cornerRadius: Theme.Radius.hover, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
    }
}

private struct NavigatorProfileBlock: View {
    let name: String
    let symbol: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Circle()
                    .fill(tint)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: symbol)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text("Manage profiles")
                        .font(Theme.Font.micro)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 6)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .selectionBackground(
                isSelected: isSelected,
                isHovering: hovering,
                in: RoundedRectangle(cornerRadius: Theme.Radius.hover, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
    }
}

private struct ResultRow: View {
    let entry: SettingsEntry
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: entry.category.symbol)
                    .font(Theme.Font.label)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title)
                        .font(Theme.Font.row)
                        .lineLimit(1)

                    Text(entry.category.title)
                        .font(Theme.Font.micro)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 6)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .hoverBackground(
                isActive: hovering,
                in: RoundedRectangle(cornerRadius: Theme.Radius.hover, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .help(Text(entry.detail))
    }
}
