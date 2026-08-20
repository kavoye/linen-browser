// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation
import os

nonisolated struct GitHubRelease: Decodable, Equatable, Identifiable, Sendable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let publishedAt: Date?
    let isPrerelease: Bool
    let isDraft: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case isPrerelease = "prerelease"
        case isDraft = "draft"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        htmlURL = try container.decode(URL.self, forKey: .htmlURL)
        publishedAt = try container.decodeIfPresent(Date.self, forKey: .publishedAt)
        isPrerelease = try container.decodeIfPresent(Bool.self, forKey: .isPrerelease) ?? false
        isDraft = try container.decodeIfPresent(Bool.self, forKey: .isDraft) ?? false
    }

    var id: String {
        tagName
    }

    var displayTitle: String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return name
        }
        return tagName
    }

    /// `v0.1.1` and `0.1.1` name the same version.
    var version: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }
}

@MainActor
@Observable
final class ReleaseNotesModel {
    private static let seenKey = "updates.notesSeenVersion"

    private(set) var releases: [GitHubRelease] = []
    private(set) var isLoading = false

    private var hasAttempted = false

    /// A version whose notes are not published yet stays unseen, so the next launch asks again.
    func shouldOpenForNewVersion() async -> Bool {
        guard !hasAttempted else { return false }
        hasAttempted = true

        let current = UpdateFeed.currentVersion
        let defaults = UserDefaults.standard
        guard let seen = defaults.string(forKey: Self.seenKey) else {
            defaults.set(current, forKey: Self.seenKey)
            return false
        }
        guard seen != current else { return false }

        await load()
        guard releases.contains(where: { $0.version == current }) else {
            Pipeline.log.notice("release notes: none published for \(current, privacy: .public) yet")
            return false
        }

        defaults.set(current, forKey: Self.seenKey)
        return true
    }

    func isRunning(_ release: GitHubRelease) -> Bool {
        release.version == UpdateFeed.currentVersion
    }

    func load() async {
        guard releases.isEmpty, !isLoading else { return }
        isLoading = true
        releases = await Self.fetchReleases()
        isLoading = false
    }

    func reload() async {
        releases = []
        await load()
    }

    /// Drafts belong to whoever is writing them, and the rolling `tip`
    /// pre-release is one entry that would sit above every real version.
    nonisolated static func published(_ releases: [GitHubRelease]) -> [GitHubRelease] {
        releases
            .filter { !$0.isDraft && !$0.isPrerelease }
            .sorted { left, right in
                (left.publishedAt ?? .distantPast) > (right.publishedAt ?? .distantPast)
            }
    }

    private static func fetchReleases() async -> [GitHubRelease] {
        var request = URLRequest(url: UpdateFeed.releasesAPI())
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return []
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return published(try decoder.decode([GitHubRelease].self, from: data))
        } catch {
            Pipeline.log.error("release notes: fetch failed - \(error, privacy: .public)")
            return []
        }
    }
}
