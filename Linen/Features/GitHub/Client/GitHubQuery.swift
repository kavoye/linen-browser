// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum GitHubQuery {
    static let search = """
    query LinenPullRequests($query: String!, $cursor: String) {
      search(query: $query, type: ISSUE_ADVANCED, first: 50, after: $cursor) {
        issueCount
        pageInfo { hasNextPage endCursor }
        nodes { ...LinenPR }
      }
    }
    \(pullRequestFields)
    """

    static let count = """
    query LinenMatchCount($query: String!) {
      search(query: $query, type: ISSUE_ADVANCED, first: 1) { issueCount }
    }
    """

    static let palette = """
    query LinenPaletteSearch($scoped: String!, $mine: String!, $repos: String!) {
      mine: search(query: $mine, type: ISSUE, first: 6) { nodes { ...LinenHit } }
      scoped: search(query: $scoped, type: ISSUE, first: 6) { nodes { ...LinenHit } }
      repos: search(query: $repos, type: REPOSITORY, first: 5) {
        nodes { ... on Repository { nameWithOwner description isPrivate url } }
      }
    }
    fragment LinenHit on SearchResultItem {
      kind: __typename
      ... on PullRequest { ...LinenPR closingIssuesReferences(first: 1) { nodes { url } } }
      ... on Issue {
        number title url issueState: state repository { nameWithOwner }
        closedByPullRequestsReferences(first: 1, includeClosedPrs: true) { nodes { url } }
      }
    }
    \(pullRequestFields)
    """

    static let single = """
    query LinenPullRequest($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) { pullRequest(number: $number) { ...LinenPR } }
    }
    \(pullRequestFields)
    """

    static let details = """
    query LinenPullRequestDetails($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          body updatedAt mergeStateStatus
          reviewRequests(first: 20) {
            nodes { requestedReviewer { kind: __typename ... on User { login avatarUrl(size: 64) } ... on Bot { login avatarUrl(size: 64) } ... on Mannequin { login avatarUrl(size: 64) } TEAMS } }
          }
          latestOpinionatedReviews(first: 20) { nodes { state author { kind: __typename login avatarUrl(size: 64) } } }
          reviewThreads(first: 100) {
            nodes { isResolved isOutdated path line comments(first: 1) { nodes { author { kind: __typename login avatarUrl(size: 64) } body bodyText url createdAt } } }
          }
          comments(last: 50) { nodes { author { kind: __typename login avatarUrl(size: 64) } body bodyText url createdAt } }
          files(first: 100) { totalCount nodes { path additions deletions } }
          closingIssuesReferences(first: 5) { nodes { number title url } }
          commits(last: 1) {
            nodes { commit { statusCheckRollup { contexts(first: 100) { nodes {
              kind: __typename
              ... on CheckRun {
                name status conclusion detailsUrl startedAt completedAt
                checkSuite { app { logoUrl(size: 32) } workflowRun { event workflow { name } } }
              }
              ... on StatusContext { context state targetUrl createdAt avatarUrl(size: 32) }
            } } } } }
          }
        }
      }
    }
    """

    static let triage = """
    query LinenInbox($review: String!, $authored: String!, $recent: String!) {
      review: search(query: $review, type: ISSUE, first: 30) { nodes { ...LinenPR } }
      authored: search(query: $authored, type: ISSUE, first: 50) { nodes { ...LinenPR } }
      recent: search(query: $recent, type: ISSUE, first: 15) { nodes { ...LinenPR } }
      LOOKUPS
    }
    \(pullRequestFields)
    """

    static let thread = """
    query LinenThread($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        issueOrPullRequest(number: $number) {
          ... on Issue { ...LinenPost comments(last: 1) { totalCount nodes { ...LinenPost } } }
          ... on PullRequest {
            ...LinenPost
            comments(last: 1) { totalCount nodes { ...LinenPost } }
            reviews(last: 3) { nodes { ...LinenPost } }
            reviewThreads(last: 1) { nodes { comments(last: 1) { nodes { ...LinenPost } } } }
          }
        }
      }
    }
    \(postFields)
    """

    static let discussion = """
    query LinenDiscussion($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) { discussion(number: $number) { ...LinenDiscussion } }
    }
    \(discussionFields)
    """

    static let discussionSearch = """
    query LinenDiscussionSearch($query: String!) {
      search(query: $query, type: DISCUSSION, first: 5) { nodes { ... on Discussion { ...LinenDiscussion } } }
    }
    \(discussionFields)
    """

    private static let discussionFields = """
    fragment LinenDiscussion on Discussion {
      title ...LinenPost
      comments(last: 1) { totalCount nodes { ...LinenPost replies(last: 1) { nodes { ...LinenPost } } } }
    }
    \(postFields)
    """

    private static let postFields = """
    fragment LinenPost on Comment { author { login avatarUrl(size: 64) } bodyText createdAt }
    """

    private static let pullRequestFields = """
    fragment LinenPR on PullRequest {
      id number title url state isDraft createdAt updatedAt reviewDecision mergeable
      additions deletions changedFiles headRefName baseRefName
      author { login avatarUrl(size: 64) }
      headRepositoryOwner { login }
      labels(first: 6) { nodes { name color } }
      repository { nameWithOwner }
      comments(last: 10) { totalCount nodes { author { login } } }
      commits(last: 1) { nodes { commit { statusCheckRollup { state contexts(first: 1) {
        totalCount checkRunCountsByState { state count } statusContextCountsByState { state count }
      } } } } }
    }
    """
}
