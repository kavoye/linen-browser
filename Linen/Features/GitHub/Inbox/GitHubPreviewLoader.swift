// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

@MainActor
@Observable
final class GitHubPreviewLoader {
    private(set) var details: [String: GitHubPRDetails] = [:]
    private(set) var looked: [String: GitHubInboxPR] = [:]
    private(set) var detailErrors: [String: String] = [:]
    private(set) var loadingDetails: Set<String> = []
    private(set) var threads: [String: GitHubThreadLoad] = [:]

    @ObservationIgnored private let client: GitHubClient
    @ObservationIgnored private let onFailure: @MainActor (Error) -> Void
    @ObservationIgnored private var connection = 0
    @ObservationIgnored private var lookedAt: [String: Date] = [:]
    @ObservationIgnored private var detailVersions: [String: String] = [:]
    @ObservationIgnored private var detailTasks: [String: Task<GitHubPRDetails?, Never>] = [:]
    @ObservationIgnored private var threadVersions: [String: Date] = [:]
    @ObservationIgnored private var threadTasks: [String: Task<Void, Never>] = [:]

    init(client: GitHubClient, onFailure: @escaping @MainActor (Error) -> Void) {
        self.client = client
        self.onFailure = onFailure
    }

    isolated deinit {
        detailTasks.values.forEach { $0.cancel() }
        threadTasks.values.forEach { $0.cancel() }
    }

    func reset() {
        connection += 1
        details = [:]
        looked = [:]
        lookedAt = [:]
        detailErrors = [:]
        detailVersions = [:]
        loadingDetails = []
        detailTasks.values.forEach { $0.cancel() }
        detailTasks = [:]
        threads = [:]
        threadVersions = [:]
        threadTasks.values.forEach { $0.cancel() }
        threadTasks = [:]
    }

    func lookedUp(_ key: String) -> (pr: GitHubInboxPR, fetchedAt: Date?)? {
        looked[key].map { ($0, lookedAt[key]) }
    }

    func noteLooked(_ pr: GitHubInboxPR) {
        looked[pr.key] = pr
        lookedAt[pr.key] = .now
    }

    func thread(for item: GitHubInboxItem) -> GitHubThreadLoad? {
        guard item.showsThread, let notification = item.notification else { return nil }
        return threads[notification.id] ?? .loading
    }

    func loadThread(for notification: GitHubNotification, token: String?, isBlocked: Bool) {
        let id = notification.id
        guard threadTasks[id] == nil else { return }
        if case .loaded = threads[id], threadVersions[id] == notification.updatedAt {
            return
        }
        guard let token, let subject = notification.thread, !isBlocked else {
            threads[id] = threads[id] ?? .failed
            return
        }
        if threads[id] == .failed {
            threads[id] = nil
        }
        let connection = connection
        threadTasks[id] = Task { [weak self] in
            guard let self else { return }
            defer {
                if connection == self.connection {
                    threadTasks[id] = nil
                }
            }
            do {
                let loaded = try await client.thread(subject, token: token)
                guard connection == self.connection else { return }
                threads[id] = .loaded(loaded)
                threadVersions[id] = notification.updatedAt
            } catch {
                guard connection == self.connection else { return }
                if threads[id] == nil {
                    threads[id] = .failed
                }
                onFailure(error)
            }
        }
    }

    @discardableResult
    func fetchDetails(
        for pr: GitHubInboxPR, token: String?, includeTeams: Bool, force: Bool, isBlocked: Bool, isThrottled: Bool
    ) -> Task<GitHubPRDetails?, Never>? {
        guard let token, let reference = pr.reference, !isBlocked else { return nil }
        if let running = detailTasks[pr.id] {
            return running
        }
        let version = "\(pr.updatedAt.timeIntervalSince1970)|\(pr.checks ?? "")|\(pr.mergeable)|\(includeTeams)"
        if !force, details[pr.id] != nil, detailVersions[pr.id] == version {
            return nil
        }
        guard !isThrottled else { return nil }
        loadingDetails.insert(pr.id)
        detailErrors[pr.id] = nil
        let connection = connection
        let task = Task { [weak self] () -> GitHubPRDetails? in
            guard let self else { return nil }
            defer {
                if connection == self.connection {
                    loadingDetails.remove(pr.id)
                    detailTasks[pr.id] = nil
                }
            }
            do {
                let loaded = try await client.pullRequestDetails(reference, includeTeams: includeTeams, token: token)
                guard connection == self.connection else { return nil }
                details[pr.id] = loaded
                detailVersions[pr.id] = version
                return loaded
            } catch {
                guard connection == self.connection else { return nil }
                detailErrors[pr.id] = error.localizedDescription
                onFailure(error)
                return nil
            }
        }
        detailTasks[pr.id] = task
        return task
    }
}
