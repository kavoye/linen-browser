// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension AppCoordinator {
    func openGitHubPage(path: String) {
        guard ["pulls", "notifications"].contains(path),
              let url = URL(string: "https://github.com/\(path)") else { return }
        if let existing = browser.tabs.first(where: { $0.committedURL == url }) {
            browser.activeTabID = existing.id
        } else {
            browser.newTab(url: url)
        }
    }

    func openGitHubLink(_ url: URL) {
        guard ["http", "https"].contains(url.scheme?.lowercased()), url.host?.isEmpty == false else { return }
        guard let reference = GitHubPullRequestReference(url: url),
              let existing = browser.tabs.first(where: {
                  !$0.isClosed && GitHubPullRequestReference(url: $0.committedURL) == reference
              }) else {
            browser.newTab(url: url)
            return
        }
        browser.activeTabID = existing.id
        if existing.committedURL != url {
            existing.load(url)
        }
    }

    func openGitHubSplit(_ primary: URL, beside secondary: URL) {
        let existing = { (url: URL) in
            self.browser.tabs.first { !$0.isClosed && $0.committedURL == url }
        }
        let first = existing(primary) ?? browser.newTab(url: primary, activate: false)
        let second = existing(secondary) ?? browser.newTab(url: secondary, activate: false)
        split(first, with: second, axis: .sideBySide)
        browser.activate(first)
    }

    @discardableResult
    func openGitHubPullRequest(
        _ reference: GitHubPullRequestReference,
        section: GitHubPullRequestSection
    ) -> BrowserTab {
        let url = reference.url(for: section)
        if let existing = browser.tabs.first(where: {
            !$0.isClosed && GitHubPullRequestReference(url: $0.committedURL) == reference
        }) {
            browser.activeTabID = existing.id
            if existing.committedURL != url {
                existing.load(url)
            }
            return existing
        }
        return browser.newTab(url: url)
    }

    func askAboutGitHubPullRequest(_ reference: GitHubPullRequestReference) {
        let tab = browser.tabs.first {
            !$0.isClosed && GitHubPullRequestReference(url: $0.committedURL) == reference
        } ?? openGitHubPullRequest(reference, section: .conversation)
        Task { [weak self] in
            guard let self, !isClosed else { return }
            let started = await handleTypedUtterance(
                String(localized: "Explain this GitHub pull request and summarize any visible check failures or review requests. Say which details are unavailable."),
                mentionedTabIDs: [tab.id],
                showsInChrome: false
            )
            if started {
                sidePanel.show(.activity)
            }
        }
    }
}
