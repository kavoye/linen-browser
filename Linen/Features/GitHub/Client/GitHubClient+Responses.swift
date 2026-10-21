// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated extension GitHubClient {
    struct APIError: Decodable {
        let message: String
        let type: String?
    }

    struct SearchEnvelope: Decodable {
        let data: SearchData?
        let errors: [APIError]?
    }

    struct SearchData: Decodable {
        let search: SearchResult
    }

    struct CountEnvelope: Decodable {
        struct Count: Decodable { let issueCount: Int }
        struct Payload: Decodable { let search: Count }
        let data: Payload?
        let errors: [APIError]?
    }

    struct SearchResult: Decodable {
        let nodes: [GitHubInboxPR?]
        let issueCount: Int
        let pageInfo: PageInfo
    }

    struct TriageEnvelope: Decodable {
        let data: [String: TriageNode?]?
        let errors: [APIError]?
    }

    struct TriageNode: Decodable {
        let nodes: [GitHubInboxPR?]?
        let pullRequest: GitHubInboxPR?
    }

    struct SingleEnvelope: Decodable {
        struct Repository: Decodable {
            let pullRequest: GitHubInboxPR?
        }
        struct Payload: Decodable {
            let repository: Repository?
        }
        let data: Payload?
        let errors: [APIError]?
    }

    struct PaletteEnvelope: Decodable {
        struct Payload: Decodable {
            let scoped: Nodes<RawHit>?
            let mine: Nodes<RawHit>?
            let repos: Nodes<RawRepository>?
        }
        let data: Payload?
        let errors: [APIError]?
    }

    struct RawLinks: Decodable {
        struct Link: Decodable {
            let url: URL
        }
        let nodes: [Link?]?

        var first: URL? {
            nodes?.compactMap { $0 }.first.flatMap { GitHubClient.webURL($0.url) }
        }
    }

    struct RawHit: Decodable {
        let hit: GitHubSearchHit?

        private enum Keys: String, CodingKey {
            case kind, number, title, url, issueState, repository, closingIssuesReferences, closedByPullRequestsReferences
        }

        private struct Repository: Decodable {
            let nameWithOwner: String
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            switch try container.decodeIfPresent(String.self, forKey: .kind) {
            case "PullRequest":
                let pr = try GitHubInboxPR(from: decoder)
                let linked = try container.decodeIfPresent(RawLinks.self, forKey: .closingIssuesReferences)?.first
                hit = pr.reference == nil ? nil : GitHubSearchHit(
                    kind: .pullRequest(pr), title: pr.title, number: pr.number,
                    repository: pr.repository.nameWithOwner, url: pr.url, linked: linked
                )
            case "Issue":
                guard let url = GitHubClient.webURL(try container.decode(URL.self, forKey: .url)) else {
                    hit = nil
                    return
                }
                hit = GitHubSearchHit(
                    kind: .issue(state: try container.decode(String.self, forKey: .issueState)),
                    title: try container.decode(String.self, forKey: .title),
                    number: try container.decode(Int.self, forKey: .number),
                    repository: try container.decode(Repository.self, forKey: .repository).nameWithOwner,
                    url: url,
                    linked: try container.decodeIfPresent(RawLinks.self, forKey: .closedByPullRequestsReferences)?.first
                )
            default:
                hit = nil
            }
        }
    }

    struct RawRepository: Decodable {
        let nameWithOwner: String?
        let description: String?
        let isPrivate: Bool?
        let url: URL?

        var hit: GitHubSearchHit? {
            guard let nameWithOwner, let url = GitHubClient.webURL(url) else { return nil }
            return GitHubSearchHit(
                kind: .repository(description: description, isPrivate: isPrivate ?? false),
                title: nameWithOwner, number: nil, repository: nameWithOwner, url: url
            )
        }
    }

    struct DetailsEnvelope: Decodable {
        struct Repository: Decodable {
            let pullRequest: RawDetails?
        }
        struct Payload: Decodable {
            let repository: Repository?
        }
        let data: Payload?
        let errors: [APIError]?
    }

    struct ThreadEnvelope: Decodable {
        struct Repository: Decodable {
            let issueOrPullRequest: RawConversation?
            let discussion: RawConversation?
        }
        struct Payload: Decodable {
            let repository: Repository?
            let search: Nodes<RawConversation>?
        }
        let data: Payload?
        let errors: [APIError]?
    }

    struct RawConversationPost: Decodable {
        let author: GitHubInboxPR.Author?
        let bodyText: String
        let createdAt: Date
        var replies: Nodes<RawConversationPost>?

        var post: GitHubThreadPreview.Post {
            GitHubThreadPreview.Post(author: author, body: bodyText, createdAt: createdAt)
        }

        var newest: RawConversationPost {
            replies?.values.last ?? self
        }
    }

    struct RawConversationThread: Decodable {
        let comments: Nodes<RawConversationPost>?
    }

    struct RawConversation: Decodable {
        let title: String?
        let author: GitHubInboxPR.Author?
        let bodyText: String?
        let createdAt: Date?
        let comments: Nodes<RawConversationPost>?
        let reviews: Nodes<RawConversationPost>?
        let reviewThreads: Nodes<RawConversationThread>?

        var preview: GitHubThreadPreview? {
            guard let bodyText, let createdAt else { return nil }
            let replies = (comments?.values ?? []).map(\.newest)
            let reviewed = (reviews?.values ?? []).filter { !$0.bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let inline = (reviewThreads?.values ?? []).flatMap { $0.comments?.values ?? [] }
            return GitHubThreadPreview(
                opening: GitHubThreadPreview.Post(author: author, body: bodyText, createdAt: createdAt),
                latest: (replies + reviewed + inline).max { $0.createdAt < $1.createdAt }?.post,
                commentCount: comments?.totalCount ?? 0
            )
        }
    }

    struct Nodes<Node: Decodable>: Decodable {
        let nodes: [Node?]?
        var totalCount: Int?

        var values: [Node] {
            (nodes ?? []).compactMap { $0 }
        }
    }

    struct RawActor: Decodable {
        let login: String?
        let name: String?
        let kind: String?
        var avatarUrl: URL?

        var actor: GitHubPRDetails.Actor? {
            login.map {
                GitHubPRDetails.Actor(login: $0, isBot: GitHubPRDetails.isBot(login: $0, kind: kind),
                                      avatarURL: GitHubAccount.avatarURL(avatarUrl))
            }
        }
    }

    struct RawComment: Decodable {
        let author: RawActor?
        let body: String?
        let bodyText: String
        let url: URL?
        let createdAt: Date?

        var comment: GitHubPRDetails.Comment {
            GitHubPRDetails.Comment(author: author?.actor, text: bodyText, markdown: String((body ?? bodyText).prefix(60_000)),
                                    url: GitHubClient.webURL(url), date: createdAt)
        }
    }

    struct RawThread: Decodable {
        let isResolved: Bool
        let isOutdated: Bool
        let path: String
        let line: Int?
        let comments: Nodes<RawComment>
    }

    struct RawCheckApp: Decodable {
        let logoUrl: URL?
    }

    struct RawWorkflowRun: Decodable {
        struct Workflow: Decodable {
            let name: String
        }
        let event: String?
        let workflow: Workflow?
    }

    struct RawCheck: Decodable {
        struct Suite: Decodable {
            let app: RawCheckApp?
            let workflowRun: RawWorkflowRun?
        }
        let kind: String?
        let name: String?
        var checkSuite: Suite?
        var startedAt: Date?
        var avatarUrl: URL?
        let status: String?
        let conclusion: String?
        let detailsUrl: URL?
        let completedAt: Date?
        let context: String?
        let state: String?
        let targetUrl: URL?
        let createdAt: Date?

        var check: GitHubPRDetails.Check? {
            if kind == "StatusContext", let context {
                let result: GitHubPRDetails.Check.State = switch state {
                case "SUCCESS":
                    .passed
                case "FAILURE", "ERROR":
                    .failed
                default:
                    .pending
                }
                return GitHubPRDetails.Check(name: context, state: result, url: GitHubClient.httpsURL(targetUrl), date: createdAt,
                                             iconURL: GitHubAccount.avatarURL(avatarUrl))
            }
            guard let name else { return nil }
            let result: GitHubPRDetails.Check.State = switch conclusion {
            case "SUCCESS", "NEUTRAL":
                .passed
            case "FAILURE", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE", "CANCELLED":
                .failed
            case "SKIPPED", "STALE":
                .skipped
            default:
                .pending
            }
            return GitHubPRDetails.Check(
                name: name, state: result, url: GitHubClient.httpsURL(detailsUrl), date: completedAt,
                workflow: checkSuite?.workflowRun?.workflow?.name, event: checkSuite?.workflowRun?.event,
                iconURL: GitHubAccount.avatarURL(checkSuite?.app?.logoUrl), startedAt: startedAt
            )
        }
    }

    struct RawRollup: Decodable {
        let contexts: Nodes<RawCheck>
    }

    struct RawCommit: Decodable {
        struct Commit: Decodable {
            let statusCheckRollup: RawRollup?
        }
        let commit: Commit
    }

    struct RawReview: Decodable {
        let state: String
        let author: RawActor?
    }

    struct RawRequest: Decodable {
        let requestedReviewer: RawActor?
    }

    struct RawFile: Decodable {
        let path: String
        let additions: Int
        let deletions: Int
    }

    struct RawIssue: Decodable {
        let number: Int
        let title: String
        let url: URL
    }

    struct RawDetails: Decodable {
        let body: String
        let updatedAt: Date
        let mergeStateStatus: String?
        let reviewRequests: Nodes<RawRequest>
        let latestOpinionatedReviews: Nodes<RawReview>
        let reviewThreads: Nodes<RawThread>
        let comments: Nodes<RawComment>
        let files: Nodes<RawFile>?
        let closingIssuesReferences: Nodes<RawIssue>?
        let commits: Nodes<RawCommit>

        var details: GitHubPRDetails {
            let checks = (commits.values.last?.commit.statusCheckRollup?.contexts.values ?? []).compactMap(\.check)
            var unique: [String: GitHubPRDetails.Check] = [:]
            for check in checks where unique[check.title].map({ check.state.rawValue < $0.state.rawValue }) ?? true {
                unique[check.title] = check
            }
            let threads = reviewThreads.values.filter { !$0.isResolved }
                .sorted { !$0.isOutdated && $1.isOutdated }
                .compactMap { thread -> GitHubPRDetails.Comment? in
                    guard var comment = thread.comments.values.first?.comment else { return nil }
                    comment.path = thread.path
                    comment.line = thread.line
                    return comment
                }
            return GitHubPRDetails(
                summary: GitHubPRDetails.readable(String(body.prefix(60_000))),
                mergeState: mergeStateStatus,
                checks: unique.values.sorted { ($0.state.rawValue, $0.title) < ($1.state.rawValue, $1.title) },
                reviews: latestOpinionatedReviews.values.compactMap { review in
                    review.author?.actor.map { GitHubPRDetails.Review(author: $0, state: review.state) }
                },
                pendingReviewers: reviewRequests.values.compactMap { request in
                    request.requestedReviewer.flatMap { reviewer in
                        (reviewer.login ?? reviewer.name).map {
                            GitHubPRDetails.Actor(login: $0, isBot: GitHubPRDetails.isBot(login: $0, kind: reviewer.kind),
                                                  avatarURL: GitHubAccount.avatarURL(reviewer.avatarUrl))
                        }
                    }
                },
                hiddenTeams: reviewRequests.values.filter { $0.requestedReviewer?.kind == "Team" && $0.requestedReviewer?.name == nil }.count,
                threads: threads,
                comments: comments.values.map(\.comment).reversed(),
                files: (files?.values ?? []).map { GitHubPRDetails.File(path: $0.path, additions: $0.additions, deletions: $0.deletions) },
                fileCount: files?.totalCount ?? 0,
                issues: (closingIssuesReferences?.values ?? []).compactMap { issue in
                    GitHubClient.webURL(issue.url).map { GitHubPRDetails.Issue(number: issue.number, title: issue.title, url: $0) }
                },
                updatedAt: updatedAt
            )
        }
    }

    struct PageInfo: Decodable {
        let hasNextPage: Bool
        let endCursor: String?
    }
}
