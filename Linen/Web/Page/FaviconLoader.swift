// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import CryptoKit
import Foundation
import WebKit

@MainActor
final class FaviconLoader {
    static let shared = FaviconLoader()

    private var cache: [String: NSImage] = [:]
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private var cacheDirectory: URL
    private let session: URLSession

    var persistsToDisk = true

    func use(cacheDirectory: URL) {
        guard cacheDirectory != self.cacheDirectory else { return }
        self.cacheDirectory = cacheDirectory
        profileGeneration &+= 1
        cache.removeAll()
        for task in inFlight.values {
            task.cancel()
        }
        inFlight.removeAll()
        sessionOnly.removeAll()
        guessed.removeAll()
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    private var profileGeneration = 0

    static func cacheDirectory(for profile: Profile) -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Linen", isDirectory: true)
            .appendingPathComponent("Favicons", isDirectory: true)
        return profile.isOriginal ? root : root.appendingPathComponent(profile.id.uuidString, isDirectory: true)
    }

    private var sessionOnly: [String: NSImage] = [:]
    private lazy var ephemeralSession = URLSession(configuration: .ephemeral)

    private static let guessExtension = "guess"

    private var guessed: Set<String> = []

    enum IconScheme: String {
        case light
        case dark
    }

    var schemeOverride: IconScheme?

    var scheme: IconScheme {
        if let schemeOverride {
            return schemeOverride
        }
        return NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }

    private func key(_ host: String) -> String {
        let host = host.lowercased()
        return scheme == .dark ? host + "#dark" : host
    }

    init(cacheDirectory: URL? = nil, session: URLSession = .shared) {
        self.cacheDirectory = cacheDirectory ?? Self.defaultCacheDirectory
        self.session = session
    }

    func forgetSessionOnlyIcons() {
        sessionOnly.removeAll()
    }

    func cached(for host: String) -> NSImage? {
        let key = key(host)
        if let image = sessionOnly[key] ?? cache[key] {
            return image
        }

        for isGuess in [false, true] {
            let file = cacheFile(for: key, isGuess: isGuess)
            guard let data = try? Data(contentsOf: file),
                  let image = NSImage(data: data),
                  image.isValid else { continue }
            cache[key] = image
            if isGuess {
                guessed.insert(key)
            }
            return image
        }
        return nil
    }

    func isGuessedIcon(for host: String) -> Bool {
        guessed.contains(key(host))
    }

    func forget(host: String) {
        let key = key(host)
        cache[key] = nil
        sessionOnly[key] = nil
        guessed.remove(key)
        try? FileManager.default.removeItem(at: cacheFile(for: key))
        try? FileManager.default.removeItem(at: cacheFile(for: key, isGuess: true))
    }

    func load(forHost host: String) async -> NSImage? {
        let host = host.lowercased()
        if let hit = cached(for: host) {
            return hit
        }
        guard let url = URL(string: "https://\(host)/favicon.ico") else { return nil }

        return await coalesced(key: key(host)) { [weak self] in
            await self?.fetchAndCache(url, forHost: host, isGuess: true)
        }
    }

    func load(for webView: WKWebView) async -> NSImage? {
        guard let pageURL = webView.url, let rawHost = pageURL.host() else { return nil }
        let host = rawHost.lowercased()
        if let hit = cached(for: host), !guessed.contains(key(host)) {
            return hit
        }

        return await coalesced(key: key(host)) { [weak self] in
            guard let self else { return nil }
            return await fetchDeclared(from: webView, pageURL: pageURL, host: host)
                ?? cached(for: host)
        }
    }

    private func fetchDeclared(from webView: WKWebView, pageURL: URL, host: String) async -> NSImage? {
        let beganPrivately = !persistsToDisk
        let beganInGeneration = profileGeneration
        var candidates: [URL] = []
        var mask: URL?
        let script = """
        (() => {
          const matches = l => {
            if (!l.media) { return true; }
            try { return window.matchMedia(l.media).matches; } catch (e) { return true; }
          };
          const rels = l => (l.getAttribute('rel') || '').toLowerCase().split(/\\s+/);
          const all = Array.from(
            document.querySelectorAll('link[rel~="icon"], link[rel~="apple-touch-icon"]')
          ).filter(l => l.href);
          const masks = Array.from(document.querySelectorAll('link[rel~="mask-icon"]'))
            .filter(l => l.href && matches(l));
          const scoped = all.some(matches) ? all.filter(matches) : all;

          const icons = scoped.filter(l => rels(l).includes('icon'));
          const tiles = scoped.filter(l => !rels(l).includes('icon'));

          const side = l => {
            const raw = (l.getAttribute('sizes') || '').toLowerCase();
            if (raw === 'any') { return 1024; }
            let best = 0;
            for (const part of raw.split(/\\s+/)) {
              const n = parseInt(part, 10);
              if (!isNaN(n)) { best = Math.max(best, n); }
            }
            return best;
          };

          const rank = list => {
            const vector = list.filter(
              l => (l.type || '').includes('svg') || /\\.svg(\\?|$)/i.test(l.href)
            );
            if (vector.length) { return vector[vector.length - 1]; }
            const sized = list.filter(l => side(l) >= 32).sort((a, b) => side(a) - side(b));
            if (sized.length) { return sized[0]; }
            return list[list.length - 1];
          };

          const pick = icons.length ? rank(icons) : (tiles.length ? rank(tiles) : null);
          const mask = masks.length ? masks[masks.length - 1] : null;
          return JSON.stringify({
            host: location.hostname || '',
            href: pick ? pick.href : '',
            mask: mask ? mask.href : ''
          });
        })()
        """
        if webView.url?.host()?.lowercased() == host,
           let answer = (try? await webView.evaluateJavaScript(script)) as? String,
           webView.url?.host()?.lowercased() == host,
           let answered = Self.declaredIconURL(fromAnswer: answer, requestedHost: host, pageURL: pageURL) {
            candidates.append(answered)
            mask = Self.declaredMaskURL(fromAnswer: answer, requestedHost: host, pageURL: pageURL)
        }
        if var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) {
            components.path = "/favicon.ico"
            components.query = nil
            components.fragment = nil
            if let fallback = components.url {
                candidates.append(fallback)
            }
        }

        for candidate in candidates {
            guard let data = await fetch(candidate) else { continue }
            guard beganInGeneration == profileGeneration else { return nil }
            let sessionOnly = beganPrivately || !persistsToDisk
            if let inked = await inked(data, mask: mask),
               let image = store(inked, forHost: host, sessionOnly: sessionOnly, isGuess: false) {
                return image
            }
            if let image = store(data, forHost: host, sessionOnly: sessionOnly, isGuess: false) {
                return image
            }
        }
        return nil
    }

    private func inked(_ data: Data, mask: URL?) async -> Data? {
        let isDark = scheme == .dark
        guard FaviconInk.needsInk(data, isDark: isDark) else { return nil }
        if let mask,
           let maskData = await fetch(mask),
           let fromMask = FaviconInk.inked(maskData, isDark: isDark) {
            return fromMask
        }
        return FaviconInk.inked(data, isDark: isDark)
    }

    private func fetch(_ url: URL) async -> Data? {
        guard Self.isFetchable(url) else { return nil }
        let session = persistsToDisk ? session : ephemeralSession
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true
        else { return nil }
        return data
    }

    func clear(modifiedSince cutoff: Date) {
        cache.removeAll()
        sessionOnly.removeAll()
        guessed.removeAll()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for file in files {
            let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if modified.map({ $0 >= cutoff }) ?? true {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    @discardableResult
    func store(_ data: Data, forHost host: String) -> NSImage? {
        store(data, forHost: host, sessionOnly: !persistsToDisk, isGuess: false)
    }

    private func store(
        _ data: Data,
        forHost host: String,
        sessionOnly keepInMemory: Bool,
        isGuess: Bool
    ) -> NSImage? {
        guard data.count <= 5 * 1_024 * 1_024,
              let image = NSImage(data: data),
              image.isValid,
              Self.carriesAnImage(data) else { return nil }

        let key = key(host)
        if isGuess {
            guessed.insert(key)
        } else {
            guessed.remove(key)
        }
        guard !keepInMemory else {
            sessionOnly[key] = image
            return image
        }
        cache[key] = image
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: cacheFile(for: key, isGuess: isGuess), options: .atomic)
        if !isGuess {
            try? FileManager.default.removeItem(at: cacheFile(for: key, isGuess: true))
        }
        return image
    }

    nonisolated static func carriesAnImage(_ data: Data) -> Bool {
        // NSBitmapImageRep decodes no vector data, so an SVG icon needs rasterising first.
        guard let rep = FaviconInk.bitmap(data) else { return false }
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                if let colour = rep.colorAt(x: x, y: y), colour.alphaComponent > 0.01 {
                    return true
                }
            }
        }
        return false
    }

    private func coalesced(key: String, work: @escaping @MainActor () async -> NSImage?) async -> NSImage? {
        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task { @MainActor in await work() }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        return image
    }

    nonisolated static func declaredIconURL(
        fromAnswer answer: String,
        requestedHost: String,
        pageURL: URL
    ) -> URL? {
        guard let data = answer.data(using: .utf8),
              let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: String],
              let documentHost = parsed["host"],
              documentHost.lowercased() == requestedHost.lowercased(),
              let href = parsed["href"],
              !href.isEmpty
        else { return nil }
        return URL(string: href, relativeTo: pageURL)
    }

    nonisolated static func declaredMaskURL(
        fromAnswer answer: String,
        requestedHost: String,
        pageURL: URL
    ) -> URL? {
        guard let data = answer.data(using: .utf8),
              let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: String],
              let documentHost = parsed["host"],
              documentHost.lowercased() == requestedHost.lowercased(),
              let mask = parsed["mask"],
              !mask.isEmpty
        else { return nil }
        return URL(string: mask, relativeTo: pageURL)
    }

    nonisolated static func isFetchable(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "https" || scheme == "http"
    }

    private func fetchAndCache(_ url: URL, forHost host: String, isGuess: Bool = false) async -> NSImage? {
        let beganPrivately = !persistsToDisk
        let beganInGeneration = profileGeneration
        guard let data = await fetch(url) else { return nil }
        guard beganInGeneration == profileGeneration else { return nil }
        return store(
            data,
            forHost: host,
            sessionOnly: beganPrivately || !persistsToDisk,
            isGuess: isGuess
        )
    }

    private func cacheFile(for key: String, isGuess: Bool = false) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return cacheDirectory
            .appendingPathComponent(name)
            .appendingPathExtension(isGuess ? Self.guessExtension : "favicon")
    }

    private static var defaultCacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Linen", isDirectory: true)
            .appendingPathComponent("Favicons", isDirectory: true)
    }
}
