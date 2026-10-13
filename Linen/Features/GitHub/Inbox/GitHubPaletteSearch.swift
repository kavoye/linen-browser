// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

nonisolated struct GitHubSearchHit: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case repository(description: String?, isPrivate: Bool)
        case pullRequest(GitHubInboxPR)
        case issue(state: String)
    }

    let kind: Kind
    let title: String
    let number: Int?
    let repository: String
    let url: URL
    var linked: URL?

    var id: String {
        url.absoluteString
    }
}

nonisolated enum GitHubPaletteRoute: Equatable, Sendable {
    case number(repository: String, number: Int)
    case repository(String)
    case search(String)
    case empty

    static func of(_ query: String, context: String?) -> Self {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .empty }
        if let match = text.wholeMatch(of: /#?(\d{1,7})/), let context, let number = Int(match.1) {
            return .number(repository: context, number: number)
        }
        if let match = text.wholeMatch(of: /([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)#(\d{1,7})/),
           GitHubPaletteRoute.isRepository(String(match.1)), let number = Int(match.2) {
            return .number(repository: String(match.1), number: number)
        }
        if GitHubPaletteRoute.isRepository(text) {
            return .repository(text)
        }
        return .search(text)
    }

    static func isRepository(_ text: String) -> Bool {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 2 && parts.allSatisfy { part in
            !part.isEmpty && part != "." && part != ".." && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
        }
    }

    static func repository(of url: URL?) -> String? {
        guard let url, url.scheme == "https", url.host == "github.com" else { return nil }
        let parts = url.path.split(separator: "/").prefix(2).map(String.init)
        let reserved: Set<String> = [
            "about", "apps", "codespaces", "collections", "dashboard", "enterprise", "explore", "features",
            "issues", "login", "marketplace", "new", "notifications", "orgs", "pricing", "pulls", "search",
            "settings", "sponsors", "topics", "trending",
        ]
        guard parts.count == 2, !reserved.contains(parts[0].lowercased()) else { return nil }
        let name = "\(parts[0])/\(parts[1])"
        return isRepository(name) ? name : nil
    }
}

nonisolated enum GitHubRepositoryPage: CaseIterable, Sendable {
    case pullRequests, issues, actions, releases, newIssue

    var title: LocalizedStringResource {
        switch self {
        case .pullRequests:
            "Pull requests"
        case .issues:
            "Issues"
        case .actions:
            LocalizedStringResource("github.page.actions", defaultValue: "Actions")
        case .releases:
            "Releases"
        case .newIssue:
            "New issue"
        }
    }

    var symbol: String {
        switch self {
        case .pullRequests:
            "arrow.triangle.pull"
        case .issues:
            "smallcircle.filled.circle"
        case .actions:
            "play.circle"
        case .releases:
            "tag"
        case .newIssue:
            "plus.circle"
        }
    }

    func url(in repository: String) -> URL? {
        let path = switch self {
        case .pullRequests:
            "pulls"
        case .issues:
            "issues"
        case .actions:
            "actions"
        case .releases:
            "releases"
        case .newIssue:
            "issues/new"
        }
        guard GitHubPaletteRoute.isRepository(repository) else { return nil }
        return URL(string: "https://github.com/\(repository)/\(path)")
    }
}

@MainActor
@Observable
final class GitHubPaletteSearch {
    private(set) var hits: [GitHubSearchHit] = []
    private(set) var hitsQuery = ""
    @ObservationIgnored var onChange: () -> Void = {}
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var cache: [String: [GitHubSearchHit]] = [:]

    private static let pause: Duration = .milliseconds(350)

    func update(_ query: String, model: GitHubPanelModel) {
        task?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3, case .search = GitHubPaletteRoute.of(text, context: nil) else {
            set([], for: text)
            return
        }
        if let cached = cache[text.lowercased()] {
            set(cached, for: text)
            return
        }
        task = Task { [weak self] in
            try? await Task.sleep(for: Self.pause)
            guard !Task.isCancelled else { return }
            let found = await model.paletteSearch(text)
            guard !Task.isCancelled, let self else { return }
            guard let found else {
                set([], for: text)
                return
            }
            cache[text.lowercased()] = found
            set(found, for: text)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private func set(_ found: [GitHubSearchHit], for query: String) {
        guard found != hits || query != hitsQuery else { return }
        hits = found
        hitsQuery = query
        onChange()
    }
}
