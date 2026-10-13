// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct GitHubConnectView: View {
    let model: GitHubPanelModel
    let onAuthorize: @MainActor (URL) -> Void
    @State private var includePrivate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "arrow.triangle.branch")
                .font(.title2).foregroundStyle(.secondary)
            Text("Keep track of your pull requests").font(.title3.weight(.semibold))
            if !model.isPrivate, model.deviceCode == nil {
                GitHubFeatureList()
                    .padding(.vertical, 4)
            }
            if model.isPrivate {
                Text("GitHub is unavailable in Private Browsing.")
                    .font(.callout).foregroundStyle(.secondary)
            } else if let code = model.deviceCode {
                GitHubDeviceCodeCard(code: code.userCode) { onAuthorize(code.verificationUri) }
                    .padding(.top, 4)
                HStack(spacing: 8) {
                    Spinner(size: 12).foregroundStyle(.secondary)
                    Text("Waiting for approval…")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel", action: model.cancelSignIn)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            } else {
                if model.isConfigured {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Include private repositories", isOn: $includePrivate)
                        if includePrivate {
                            Text("GitHub’s access to private repositories also allows changes. Linen only reads them, and marks notifications as read when you ask.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            ToolbarChip(symbol: "person.crop.circle", label: "Connect GitHub") {
                                model.connect(includePrivate: includePrivate, open: onAuthorize)
                            }
                            .disabled(model.isConnecting)
                            if model.isConnecting {
                                Spinner(size: 12).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .gitHubConnectBox()
                } else {
                    Text("GitHub sign-in isn’t set up in this build.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            if let error = model.errorMessage {
                Text(verbatim: error).font(.caption).foregroundStyle(Theme.warning)
            }
            if model.needsReconnect {
                Button("Disconnect", role: .destructive, action: model.disconnect)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
    }
}

private struct GitHubFeatureList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            row("bell.badge", "Get notified when your pull requests get reviews, comments, or check results.")
            row("rectangle.on.rectangle", "See a pull request’s status when you hover over its tab.")
            row("eye", "Shift-click a pull request link to peek at its checks and reviews.")
            row("magnifyingglass", "Type “github” in the address bar and press Tab to search pull requests.")
            row("quote.bubble", "Ask the assistant to explain a pull request or a failing check.")
        }
    }

    private func row(_ symbol: String, _ text: LocalizedStringResource) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct GitHubDeviceCodeCard: View {
    let code: String
    let onOpen: () -> Void
    @State private var copyID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paste this code on GitHub to connect Linen. It’s already copied.")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(verbatim: code)
                    .font(.title.monospaced().weight(.semibold))
                    .textSelection(.enabled)
                Button(action: copy) {
                    Image(systemName: copyID == nil ? "doc.on.doc" : "checkmark")
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(Text("Copy Code"))
                .accessibilityLabel(Text("Copy Code"))
            }
            Button("Open GitHub") {
                copy()
                onOpen()
            }
        }
        .gitHubConnectBox()
        .onAppear(perform: copy)
        .task(id: copyID) {
            guard copyID != nil else { return }
            do {
                try await Task.sleep(for: .seconds(1))
                copyID = nil
            } catch {}
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        copyID = UUID()
    }
}

private extension View {
    func gitHubConnectBox() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Wash.faint, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.Wash.hairline))
    }
}

struct GitHubFilterEditor: View {
    let filter: GitHubFilter
    let matchCount: (String) async throws -> Int?
    let onSave: (GitHubFilter) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var symbol = ""
    @State private var parts = GitHubFilterQuery(state: .open, sort: .updated, qualifiers: "")
    @State private var choosingSymbol = false
    @State private var matches = Matches.idle
    @FocusState private var nameFocused: Bool

    private enum Matches: Equatable {
        case idle, checking, found(Int), failed(String)
    }

    private var query: String {
        parts.query
    }

    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 80 && !query.isEmpty && query.count <= 1000
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(filter.name.isEmpty ? "New Filter" : "Edit Filter").font(.headline)
            HStack(spacing: 10) {
                Button { choosingSymbol.toggle() } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 15))
                        .frame(width: 34, height: 34)
                        .background(Theme.Wash.faint, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Choose an icon")
                .accessibilityLabel("Icon")
                .popover(isPresented: $choosingSymbol, arrowEdge: .bottom) { symbolGrid }
                TextField("Name", text: $name)
                    .textFieldStyle(.plain).font(.title3).focused($nameFocused)
                    .padding(.horizontal, 10).frame(height: 34)
                    .background(Theme.Wash.faint, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Search").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    TextField("Search", text: $parts.qualifiers, prompt: Text(verbatim: "involves:@me (label:bug OR label:crash)"), axis: .vertical)
                        .labelsHidden().textFieldStyle(.plain)
                        .font(.body.monospaced())
                        .lineLimit(3...6)
                        .padding(10)
                    Divider()
                    HStack(spacing: 8) {
                        qualifierMenu
                        Spacer(minLength: 8)
                        matchLabel
                    }
                    .padding(.horizontal, 8).frame(height: 30)
                }
                .background(Theme.Wash.faint, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control).strokeBorder(Theme.Wash.hairline))
            }
            HStack(spacing: 16) {
                Picker("Show", selection: $parts.state) {
                    Text(LocalizedStringResource("github.filter.state.open", defaultValue: "Open")).tag(GitHubFilterState.open)
                    Text("Draft").tag(GitHubFilterState.draft)
                    Text("Merged").tag(GitHubFilterState.merged)
                    Text("Closed").tag(GitHubFilterState.closed)
                    Divider()
                    Text("All").tag(GitHubFilterState.all)
                }
                .fixedSize()
                Picker("Sorted by", selection: $parts.sort) {
                    Text("Best match").tag(GitHubFilterSort.bestMatch)
                    Divider()
                    Text("Recently updated").tag(GitHubFilterSort.updated)
                    Text("Least recently updated").tag(GitHubFilterSort.leastUpdated)
                    Text("Newest").tag(GitHubFilterSort.newest)
                    Text("Oldest").tag(GitHubFilterSort.oldest)
                    Divider()
                    Text("Most commented").tag(GitHubFilterSort.comments)
                    Text("Most reactions").tag(GitHubFilterSort.reactions)
                    Text("Most interactions").tag(GitHubFilterSort.interactions)
                }
                .fixedSize()
            }
            Text("Combine terms with AND, OR, and parentheses. Use @me for your GitHub account.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(GitHubFilter(id: filter.id, name: name, query: query, symbol: symbol))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            name = filter.name
            symbol = filter.symbolName
            parts = GitHubFilterQuery(filter.query)
            nameFocused = filter.name.isEmpty
        }
        .task(id: query) { await countMatches() }
    }

    @ViewBuilder
    private var matchLabel: some View {
        switch matches {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView().controlSize(.mini)
        case .found(let count):
            Text("\(count) pull requests").font(Theme.Font.caption).foregroundStyle(.secondary).monospacedDigit()
        case .failed(let message):
            Label("GitHub can’t run this search", systemImage: "exclamationmark.triangle.fill")
                .font(Theme.Font.caption).foregroundStyle(.secondary)
                .help(Text(verbatim: message))
        }
    }

    private var qualifierMenu: some View {
        Menu {
            Section("People") { tokens("author:@me", "assignee:@me", "mentions:@me", "involves:@me", "commenter:@me") }
            Section("Review") {
                tokens("review-requested:@me", "reviewed-by:@me", "review:none", "review:required", "review:approved", "review:changes_requested")
            }
            Section("Checks") { tokens("status:success", "status:failure", "status:pending") }
            Section("Where") { tokens("repo:", "org:", "base:", "head:", "label:", "-label:", "no:label", "milestone:", "no:assignee") }
            Section("Dates") {
                Button("Updated in the last week") { insert("updated:>=" + Self.day(daysAgo: 7)) }
                Button("Created in the last month") { insert("created:>=" + Self.day(daysAgo: 30)) }
            }
            Section("Logic") { tokens("OR", "AND", "(", ")") }
        } label: {
            Label("Qualifier", systemImage: "plus").font(Theme.Font.control)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func tokens(_ values: String...) -> some View {
        ForEach(values, id: \.self) { token in
            Button { insert(token) } label: { Text(verbatim: token) }
        }
    }

    private static func day(daysAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        return date.formatted(.iso8601.year().month().day())
    }

    private func countMatches() async {
        do {
            try await Task.sleep(for: .milliseconds(500))
        } catch {
            return
        }
        matches = .checking
        do {
            let found = try await matchCount(query)
            guard !Task.isCancelled else { return }
            matches = found.map(Matches.found) ?? .idle
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            matches = .failed(error.localizedDescription)
        }
    }

    private var symbolGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 6), spacing: 4) {
            ForEach(GitHubFilter.symbolChoices, id: \.self) { choice in
                Button {
                    symbol = choice
                    choosingSymbol = false
                } label: {
                    Image(systemName: choice)
                        .foregroundStyle(choice == symbol ? Theme.accent : .primary)
                        .frame(width: 30, height: 28)
                        .background(choice == symbol ? Theme.Wash.selection : .clear,
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(choice == symbol ? [.isSelected] : [])
            }
        }
        .padding(10)
    }

    private func insert(_ token: String) {
        let trimmed = parts.qualifiers.trimmingCharacters(in: .whitespaces)
        parts.qualifiers = trimmed.isEmpty || trimmed.hasSuffix("(") || token == ")" ? trimmed + token : trimmed + " " + token
    }
}
