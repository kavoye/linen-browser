// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import Testing

@testable import Linen

@MainActor
struct GitHubPanelLayoutTests {
    @Test func rendersCustomFilterMenu() async throws {
        let menu = GitHubFilterMenu(filters: GitHubFilter.defaults, selectedID: "involved", onSelect: { _ in },
                                   onNew: {}, onEdit: { _ in }, onDelete: { _ in }, onDismiss: {})
            .background(Theme.windowBackground).environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: menu)
        let size = host.fittingSize
        #expect(size.width <= 320)
        #expect(size.height <= 480)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        window.display()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(filePath: "/tmp/linen-github-filters.png"))
    }

    @Test func rendersInboxAndDetailsAtSidebarAndExpandedWidths() async throws {
        let credentials = GitHubTestCredentials()
        let id = UUID()
        try GitHubConnectionStore(profileID: id, storage: credentials.storage).save("fixture")
        let client = GitHubClient { request in
            let json: String
            switch request.url!.path {
            case "/user":
                json = #"{"login":"octocat","name":"Octo Cat"}"#
            case "/graphql" where String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("LinenPullRequestDetails"):
                json = GitHubFixtures.details
            case "/graphql":
                json = Self.pullRequests
            default:
                json = Self.notifications
            }
            let dated = json.replacingOccurrences(of: "2026-10-06T00:20:00Z", with: Date.now.addingTimeInterval(-600).ISO8601Format())
                .replacingOccurrences(of: "2026-10-05T23:20:00Z", with: Date.now.addingTimeInterval(-3600).ISO8601Format())
            return (Data(dated.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                                   headerFields: ["X-OAuth-Scopes": "repo, notifications"])!)
        }
        let defaults = TestDefaults.suite("GitHubLayout")
        let model = GitHubPanelModel(profileID: id, defaults: defaults, client: client, storage: credentials.storage)
        model.start()
        defer { model.disconnect() }
        try #require(await waitUntil { model.lastUpdated != nil })
        #expect(model.sections.map(\.kind) == [.needsYou, .authored, .recent])
        for (name, width, selection) in [
            ("list", 300.0, false),
            ("detail", 300.0, true),
            ("expanded", 1050.0, true),
        ] {
            if selection, let pr = model.triage.reviewRequested.first {
                model.select(pr)
                try #require(await waitUntil { model.details[pr.id] != nil })
                if name == "detail" {
                    let detail = GitHubPRDetail(
                        pr: pr, details: model.details[pr.id], isLoading: false, error: nil, showsBack: true,
                        onBack: {}, onOpen: { _, _ in }, onOpenURL: { _ in }, onAsk: { _ in }, onRetry: {}
                    )
                    .padding(18).frame(width: width).background(Theme.windowBackground).environment(\.colorScheme, .dark)
                    let renderer = ImageRenderer(content: detail)
                    renderer.scale = 2
                    var image: NSImage?
                    NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance { image = renderer.nsImage }
                    let tiff = try #require(image?.tiffRepresentation)
                    let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
                    try png.write(to: URL(filePath: "/tmp/linen-github-pr-detail.png"))
                    let preview = GitHubPRPreview(pr: pr, details: model.details[pr.id])
                        .background(Theme.windowBackground).environment(\.colorScheme, .dark)
                    let previewRenderer = ImageRenderer(content: preview)
                    previewRenderer.scale = 2
                    var previewImage: NSImage?
                    NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance { previewImage = previewRenderer.nsImage }
                    let previewTIFF = try #require(previewImage?.tiffRepresentation)
                    try #require(NSBitmapImageRep(data: previewTIFF)?.representation(using: .png, properties: [:]))
                        .write(to: URL(filePath: "/tmp/linen-github-preview.png"))
                }
            } else {
                model.clearSelection()
            }
            let view = GitHubInboxView(model: model, onAuthorize: { _ in }, onOpen: { _, _ in }, onAsk: { _ in })
                .frame(width: width, height: 720)
                .background(Theme.windowBackground)
                .environment(\.colorScheme, .dark)
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 720),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderBack(nil)
            // Native glass needs the window compositor for live visual inspection.
            if name == "list", ProcessInfo.processInfo.environment["LINEN_GITHUB_UI_TEST"] == "1" {
                window.title = "GitHub panel preview"
                window.styleMask = [.titled, .closable]
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                try await Task.sleep(for: .seconds(50))
            }
            try await Task.sleep(for: .milliseconds(150))
            host.layoutSubtreeIfNeeded()
            window.display()
            #expect(host.fittingSize.width <= width + 1)
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(filePath: "/tmp/linen-github-\(name).png"))
            window.close()
        }
    }

    private nonisolated static let pullRequests = #"""
    {"data":{"authored":{"nodes":[{
      "id":"PR_2","number":2,"title":"fix(extensions): Fix startup of Chrome iCloud Passwords",
      "url":"https://github.com/kavoye/linen-browser/pull/2","state":"OPEN","isDraft":true,
      "updatedAt":"2026-10-06T00:20:00Z","reviewDecision":null,"mergeable":"MERGEABLE",
      "additions":263,"deletions":1,"changedFiles":3,"headRefName":"fix/extension-api-stand-ins","baseRefName":"main",
      "author":{"login":"octocat"},"repository":{"nameWithOwner":"kavoye/linen-browser"},"comments":{"totalCount":1},
      "commits":{"nodes":[{"commit":{"statusCheckRollup":null}}]}
    }]},"review":{"nodes":[{
      "id":"PR_42","number":42,"title":"Add keyboard shortcuts to the command menu",
      "url":"https://github.com/kavoye/linen-browser/pull/42","state":"OPEN","isDraft":false,
      "updatedAt":"2026-10-05T23:20:00Z","reviewDecision":"CHANGES_REQUESTED","mergeable":"CONFLICTING",
      "additions":80,"deletions":12,"changedFiles":5,"headRefName":"keyboard-shortcuts","baseRefName":"main",
      "author":{"login":"mira"},"headRepositoryOwner":{"login":"mira"},
      "labels":{"nodes":[{"name":"bug","color":"d73a4a"},{"name":"extensions","color":"0e8a16"},{"name":"needs review","color":"fbca04"},{"name":"macOS 27","color":"5319e7"}]},
      "repository":{"nameWithOwner":"kavoye/linen-browser"},"comments":{"totalCount":6},
      "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"FAILURE","contexts":{"totalCount":12,"checkRunCountsByState":[{"state":"SUCCESS","count":11},{"state":"FAILURE","count":1}]}}}}]}
    }]},"recent":{"nodes":[{
      "id":"PR_50","number":50,"title":"Open an issue and its pull request in split view",
      "url":"https://github.com/kavoye/linen-browser/pull/50","state":"OPEN","isDraft":false,
      "createdAt":"2026-10-06T00:20:00Z","updatedAt":"2026-10-06T00:20:00Z","reviewDecision":"REVIEW_REQUIRED","mergeable":"MERGEABLE",
      "additions":40,"deletions":2,"changedFiles":2,"headRefName":"split-issue","baseRefName":"main",
      "author":{"login":"alex"},"repository":{"nameWithOwner":"kavoye/linen-browser"},"comments":{"totalCount":0},
      "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"PENDING"}}}]}
    }]}}}
    """#

    private nonisolated static let notifications = #"""
    [{"id":"123","unread":true,"reason":"comment","updated_at":"2026-10-06T00:20:00Z",
      "subject":{"title":"Improved pull request Files Changed experience feedback","type":"Discussion",
      "url":"https://api.github.com/repos/community/community/discussions/163932"},"repository":{"full_name":"community/community"}},
     {"id":"124","unread":true,"reason":"review_requested","updated_at":"2026-10-05T23:20:00Z",
      "subject":{"title":"Add keyboard shortcuts to the command menu","type":"PullRequest",
      "url":"https://api.github.com/repos/kavoye/linen-browser/pulls/42"},"repository":{"full_name":"kavoye/linen-browser"}}]
    """#
}
