// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct GitHubPaletteActions {
    let open: (URL) -> Void
    let openCurrent: (URL) -> Void
    let split: (URL, URL) -> Void
}

enum GitHubPaletteSections {
    static func build(
        query: String,
        webItem: OmniboxItem?,
        context: String?,
        known: [String],
        mine: [GitHubInboxPR],
        hits: [GitHubSearchHit],
        hitsQuery: String,
        actions: GitHubPaletteActions
    ) -> [OmniboxSection] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var sections: [OmniboxSection] = []
        switch GitHubPaletteRoute.of(text, context: context) {
        case .empty:
            if let context {
                sections.append(pages(for: context, actions: actions))
            }
            let yours = mine.prefix(5).map { pullRequest($0, linked: nil, actions: actions) }
            if !yours.isEmpty {
                sections.append(OmniboxSection(id: "github-mine", title: String(localized: "Your pull requests"), items: yours))
            }
            let repositories = known.filter { $0.caseInsensitiveCompare(context ?? "") != .orderedSame }.prefix(5)
                .compactMap { repository($0, description: nil, isPrivate: false, actions: actions) }
            if !repositories.isEmpty {
                sections.append(OmniboxSection(id: "github-repos", title: String(localized: "Repositories"), items: repositories))
            }
            return sections

        case .number(let repository, let number):
            if let url = URL(string: "https://github.com/\(repository)/issues/\(number)") {
                sections.append(OmniboxSection(id: "github-number", title: "", items: [
                    OmniboxItem(
                        id: "github-number-\(repository)-\(number)", kind: .action,
                        title: String(localized: "Go to #\(number)"), detail: repository, symbol: "number",
                        alternate: { actions.openCurrent(url) }, run: { actions.open(url) }
                    ),
                ]))
            }

        case .repository(let name):
            sections.append(pages(for: name, actions: actions))

        case .search:
            break
        }

        if let webItem {
            sections.append(OmniboxSection(id: "site-search", title: "", items: [webItem]))
        }

        let lowered = text.lowercased()
        var seen: Set<String> = []
        var repositories = known.filter { $0.lowercased().contains(lowered) }.prefix(4)
            .compactMap { name -> OmniboxItem? in
                seen.insert(name.lowercased())
                return repository(name, description: nil, isPrivate: false, actions: actions)
            }
        let current = hitsQuery.caseInsensitiveCompare(text) == .orderedSame ? hits : []
        var work: [OmniboxItem] = []
        for hit in current {
            switch hit.kind {
            case .repository(let description, let isPrivate):
                guard seen.insert(hit.repository.lowercased()).inserted,
                      let item = repository(hit.repository, description: description, isPrivate: isPrivate, actions: actions)
                else { continue }
                repositories.append(item)
            case .pullRequest(let pr):
                work.append(pullRequest(pr, linked: hit.linked, actions: actions))
            case .issue(let state):
                work.append(issue(hit, state: state, actions: actions))
            }
        }
        if !work.isEmpty {
            sections.append(OmniboxSection(id: "github-work", title: String(localized: "Pull requests and issues"), items: work))
        }
        if !repositories.isEmpty {
            sections.append(OmniboxSection(id: "github-repos", title: String(localized: "Repositories"), items: repositories))
        }
        return sections
    }

    private static func pages(for repository: String, actions: GitHubPaletteActions) -> OmniboxSection {
        OmniboxSection(id: "github-pages", title: repository, items: GitHubRepositoryPage.allCases.compactMap { page in
            page.url(in: repository).map { url in
                OmniboxItem(
                    id: "github-page-\(repository)-\(page)", kind: .action, title: String(localized: page.title),
                    detail: repository, symbol: page.symbol,
                    alternate: { actions.openCurrent(url) }, run: { actions.open(url) }
                )
            }
        })
    }

    private static func repository(
        _ name: String, description: String?, isPrivate: Bool, actions: GitHubPaletteActions
    ) -> OmniboxItem? {
        guard GitHubPaletteRoute.isRepository(name), let url = URL(string: "https://github.com/\(name)") else { return nil }
        let detail = description.flatMap { $0.isEmpty ? nil : $0 }
            ?? (isPrivate ? String(localized: "Private repository") : String(localized: "Repository"))
        return OmniboxItem(
            id: "github-repo-\(name.lowercased())", kind: .action, title: name, detail: detail,
            symbol: isPrivate ? "lock" : "book.closed",
            alternate: { actions.openCurrent(url) }, run: { actions.open(url) }
        )
    }

    private static func pullRequest(_ pr: GitHubInboxPR, linked: URL?, actions: GitHubPaletteActions) -> OmniboxItem {
        let symbol = switch pr.state {
        case "MERGED":
            "arrow.triangle.merge"
        case "CLOSED":
            "xmark.circle"
        default:
            "arrow.triangle.pull"
        }
        let state: String = switch pr.state {
        case "MERGED":
            String(localized: "Merged")
        case "CLOSED":
            String(localized: "Closed")
        default:
            String(localized: GitHubPRStatus(pr).label)
        }
        let url = pr.url
        return OmniboxItem(
            id: "github-item-\(url.absoluteString)", kind: .action, title: pr.title,
            detail: "\(pr.repository.nameWithOwner) #\(pr.number) · \(state)", symbol: symbol,
            alternate: { linked.map { actions.split(url, $0) } ?? actions.openCurrent(url) },
            run: { actions.open(url) }
        )
    }

    private static func issue(_ hit: GitHubSearchHit, state: String, actions: GitHubPaletteActions) -> OmniboxItem {
        let url = hit.url
        let linked = hit.linked
        let closed = state == "CLOSED"
        let label = closed ? String(localized: "Closed") : String(localized: "Open")
        return OmniboxItem(
            id: "github-item-\(url.absoluteString)", kind: .action, title: hit.title,
            detail: "\(hit.repository) #\(hit.number ?? 0) · \(label)",
            symbol: closed ? "checkmark.circle" : "smallcircle.filled.circle",
            alternate: { linked.map { actions.split(url, $0) } ?? actions.openCurrent(url) },
            run: { actions.open(url) }
        )
    }
}
