// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct GitHubPanelSurface: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator

    var body: some View {
        GitHubInboxView(
            model: coordinator.github,
            onAuthorize: coordinator.openGitHubLink,
            onOpen: { coordinator.openGitHubPullRequest($0, section: $1) },
            onAsk: coordinator.askAboutGitHubPullRequest
        )
        .environment(coordinator.githubPreview)
        .task { coordinator.github.start() }
        .onAppear { coordinator.github.panelDidAppear() }
        .onDisappear { coordinator.github.panelDidDisappear() }
    }
}

struct GitHubInboxView: View {
    @Bindable var model: GitHubPanelModel
    let onAuthorize: @MainActor (URL) -> Void
    let onOpen: (GitHubPullRequestReference, GitHubPullRequestSection) -> Void
    let onAsk: (GitHubPullRequestReference) -> Void
    @State private var editingFilter: GitHubFilter?
    @State private var confirmPrivateAccess = false

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 700
            VStack(spacing: 0) {
                if model.hasConnection && !model.needsReconnect && !model.isConnecting {
                    GitHubInboxHeader(model: model, onProfile: onAuthorize, onManage: {
                        onAuthorize(URL(string: "https://github.com/settings/applications")!)
                    }, onPrivateAccess: { confirmPrivateAccess = true }) {
                        GitHubFilterPicker(
                            filters: [.inbox] + model.filters, selectedID: model.selectedFilterID, onSelect: model.selectFilter,
                            onNew: { editingFilter = GitHubFilter(id: UUID().uuidString, name: "", query: "is:open involves:@me sort:updated-desc") },
                            onEdit: { editingFilter = $0 },
                            onDelete: model.deleteFilter
                        )
                    }
                    Divider().overlay(Theme.Wash.hairline)
                    GitHubPRContent(model: model, wide: wide, onOpen: onOpen, onOpenURL: onAuthorize, onAsk: onAsk)
                    GitHubInboxFooter(model: model, onManage: {
                        onAuthorize(URL(string: "https://github.com/settings/applications")!)
                    }, onPrivateAccess: { confirmPrivateAccess = true })
                } else {
                    ScrollView {
                        GitHubConnectView(model: model, onAuthorize: onAuthorize)
                            .padding(20).frame(maxWidth: 440).frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(item: $editingFilter) { filter in
            GitHubFilterEditor(filter: filter, matchCount: model.matchCount, onSave: model.saveFilter)
        }
        .confirmationDialog("Include private repositories?", isPresented: $confirmPrivateAccess) {
            Button("Continue to GitHub") { model.connect(includePrivate: true, open: onAuthorize) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("GitHub’s access to private repositories also allows changes. Linen only reads them, and marks notifications as read when you ask.")
        }
    }
}

private struct GitHubPRContent: View {
    let model: GitHubPanelModel
    let wide: Bool
    let onOpen: (GitHubPullRequestReference, GitHubPullRequestSection) -> Void
    let onOpenURL: @MainActor (URL) -> Void
    let onAsk: (GitHubPullRequestReference) -> Void

    var body: some View {
        let selected = model.selectedPR
        HStack(spacing: 0) {
            if wide || selected == nil {
                ScrollView {
                    if model.isInbox {
                        GitHubInboxList(model: model, onOpen: onOpenURL)
                    } else {
                        GitHubPRList(model: model, onOpenURL: onOpenURL)
                    }
                }
                .frame(maxWidth: wide ? 360 : .infinity)
            }
            if wide {
                Divider()
            }
            if let selected {
                GitHubPRDetailPane(model: model, pr: selected, wide: wide, onOpen: onOpen, onOpenURL: onOpenURL, onAsk: onAsk)
            } else if wide {
                GitHubEmptyState(symbol: "arrow.triangle.pull", title: "Select a pull request", detail: "Review checks, comments, and changes here.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct GitHubPRDetailPane: View {
    let model: GitHubPanelModel
    let pr: GitHubInboxPR
    let wide: Bool
    let onOpen: (GitHubPullRequestReference, GitHubPullRequestSection) -> Void
    let onOpenURL: @MainActor (URL) -> Void
    let onAsk: (GitHubPullRequestReference) -> Void

    var body: some View {
        ScrollView {
            GitHubPRDetail(
                pr: pr, details: model.details[pr.id],
                isLoading: model.loadingDetails.contains(pr.id), error: model.detailErrors[pr.id],
                showsBack: !wide, onBack: model.clearSelection, onOpen: onOpen, onOpenURL: onOpenURL, onAsk: onAsk,
                onRetry: { model.loadDetails(for: pr, force: true) },
                onShowTeams: model.hasOrgAccess == false ? {
                    model.connect(includePrivate: model.hasPrivateAccess == true, open: onOpenURL)
                } : nil
            )
            .id(pr.id)
            .padding(18)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct GitHubPRList: View {
    let model: GitHubPanelModel
    let onOpenURL: @MainActor (URL) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 4) {
            if model.pullRequests.isEmpty {
                if model.isRefreshing {
                    GitHubListSkeleton(label: "Loading pull requests…", showsHeader: false)
                } else if model.errorMessage == nil {
                    GitHubEmptyState(symbol: "line.3.horizontal.decrease", title: "No matching pull requests",
                                     detail: "Choose another filter or edit your search.")
                } else {
                    GitHubEmptyState(symbol: "line.3.horizontal.decrease", title: "Couldn’t load pull requests",
                                     detail: "Refresh to try again.")
                }
            }
            ForEach(model.pullRequests) { pr in
                GitHubInboxRow(
                    item: GitHubInboxItem(id: pr.id, reason: .opened, pr: pr, notification: nil),
                    selected: model.selectedItemID == pr.id, markingRead: false,
                    onSelect: { model.select(pr) }, onOpen: { onOpenURL(pr.url) }, onRead: {},
                    onPreview: { model.loadDetails(for: pr) }
                )
                .equatable()
            }
            if model.nextCursor != nil {
                Button("Load more pull requests") { model.loadMore(notifications: false) }
                    .buttonStyle(GitHubRowButtonStyle())
                    .disabled(model.isLoadingMore || model.isRefreshing)
            }
            if !model.pullRequests.isEmpty {
                Text("\(model.pullRequests.count) of \(model.totalPRs) results")
                    .font(Theme.Font.caption).foregroundStyle(Theme.metaInk)
                    .padding(.horizontal, 8).padding(.vertical, 10)
            }
        }
        .padding(8)
    }
}

struct GitHubEmptyState: View {
    let symbol: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.title2).foregroundStyle(Theme.metaInk)
            Text(title).font(Theme.Font.title).foregroundStyle(.secondary)
            Text(detail).font(Theme.Font.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.vertical, 40)
    }
}

struct GitHubRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.control)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(configuration.isPressed ? Theme.Wash.selection : Theme.Wash.hover, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
    }
}
