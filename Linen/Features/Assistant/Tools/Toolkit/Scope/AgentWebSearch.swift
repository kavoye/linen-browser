// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

@MainActor
final class AgentWebSearch {
    private let search: (String) async -> [SearchHit]
    private var cache: [String: (expires: ContinuousClock.Instant, hits: [SearchHit])] = [:]
    private var generation = 0

    init(search: @escaping (String) async -> [SearchHit]) {
        self.search = search
    }

    func reset() {
        cache = [:]
        generation &+= 1
    }

    func hits(for query: String) async -> [SearchHit] {
        if let cached = cache[query], cached.expires > .now {
            return cached.hits
        }
        guard !Task.isCancelled else { return [] }
        let started = generation
        let hits = await search(query)
        guard generation == started else { return [] }
        if !hits.isEmpty, !Task.isCancelled {
            if cache.count >= 16, let oldest = cache.min(by: { $0.value.expires < $1.value.expires })?.key {
                cache[oldest] = nil
            }
            cache[query] = (.now + .seconds(120), hits)
        }
        return hits
    }
}
