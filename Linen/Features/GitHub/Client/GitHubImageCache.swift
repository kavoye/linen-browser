// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

@MainActor
final class GitHubImageCache {
    static let shared = GitHubImageCache()

    private let images = NSCache<NSURL, NSImage>()
    private var loads: [URL: Task<NSImage?, Never>] = [:]
    private var failures: [URL: Date] = [:]
    private let fetch: @Sendable (URL) async throws -> (Data, URLResponse)
    private let retryDelay: TimeInterval
    var now: () -> Date = Date.init

    init(countLimit: Int = 500, retryDelay: TimeInterval = 300, fetch: @escaping @Sendable (URL) async throws -> (Data, URLResponse) = {
        try await URLSession.shared.data(from: $0)
    }) {
        self.fetch = fetch
        self.retryDelay = retryDelay
        images.countLimit = countLimit
    }

    func cached(_ url: URL) -> NSImage? {
        images.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> NSImage? {
        if let image = cached(url) {
            return image
        }
        if let load = loads[url] {
            return await load.value
        }
        if let failed = failures[url], now().timeIntervalSince(failed) < retryDelay {
            return nil
        }
        let fetch = fetch
        let load = Task.detached(priority: .utility) { () -> NSImage? in
            guard let (data, response) = try? await fetch(url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return NSImage(data: data)
        }
        loads[url] = load
        let image = await load.value
        loads[url] = nil
        if let image {
            images.setObject(image, forKey: url as NSURL)
            failures[url] = nil
        } else {
            failures[url] = now()
        }
        return image
    }
}

struct GitHubCachedImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var loaded: Loaded?

    private struct Loaded {
        let url: URL
        let image: NSImage
    }

    var body: some View {
        let image = url.flatMap { url in
            GitHubImageCache.shared.cached(url) ?? (loaded?.url == url ? loaded?.image : nil)
        }
        ZStack {
            if let image {
                content(Image(nsImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url, GitHubImageCache.shared.cached(url) == nil,
                  let image = await GitHubImageCache.shared.image(for: url), !Task.isCancelled else { return }
            loaded = Loaded(url: url, image: image)
        }
    }
}
