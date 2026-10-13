// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct GitHubPullRequestReference: Equatable, Sendable {
    let owner: String
    let repository: String
    let number: Int

    init?(url: URL?) {
        guard let url, url.scheme == "https", url.host == "github.com",
              url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 5, parts[0].isEmpty, parts[3] == "pull",
              Self.isName(parts[1]), Self.isName(parts[2]),
              !parts[4].isEmpty, parts[4].allSatisfy({ $0.isASCII && $0.isNumber }),
              let number = Int(parts[4]), number > 0 else { return nil }
        let suffix = parts.dropFirst(5)
        guard suffix.isEmpty || (suffix.count == 1 && ["", "files", "commits", "checks", "changes"].contains(String(suffix.first!))) else { return nil }
        owner = String(parts[1])
        repository = String(parts[2])
        self.number = number
    }

    private static func isName(_ value: Substring) -> Bool {
        !value.isEmpty && value != "." && value != ".."
            && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
    }

    var repositoryName: String {
        "\(owner)/\(repository)"
    }

    var key: String {
        "\(repositoryName)#\(number)".lowercased()
    }

    var url: URL {
        URL(string: "https://github.com/\(repositoryName)/pull/\(number)")!
    }

    func url(for section: GitHubPullRequestSection) -> URL {
        section == .conversation ? url : url.appendingPathComponent(section.rawValue)
    }
}

nonisolated enum GitHubPullRequestSection: String, CaseIterable, Sendable {
    case conversation
    case files
    case commits
    case checks

    var title: LocalizedStringResource {
        switch self {
        case .conversation:
            "Conversation"
        case .files:
            "Changes"
        case .commits:
            "Commits"
        case .checks:
            "Checks"
        }
    }

    var symbol: String {
        switch self {
        case .conversation:
            "bubble.left.and.bubble.right"
        case .files:
            "plus.forwardslash.minus"
        case .commits:
            "circle.and.line.horizontal"
        case .checks:
            "checklist"
        }
    }
}
