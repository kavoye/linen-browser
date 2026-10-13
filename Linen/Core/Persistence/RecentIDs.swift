// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct RecentIDs {
    private var ids: [UUID] = []
    private let capacity: Int

    init(capacity: Int = 32) {
        self.capacity = capacity
    }

    mutating func insert(_ id: UUID) {
        ids.removeAll { $0 == id }
        ids.append(id)
        if ids.count > capacity {
            ids.removeFirst(ids.count - capacity)
        }
    }

    mutating func formUnion(_ newIDs: some Sequence<UUID>) {
        for id in newIDs {
            insert(id)
        }
    }

    mutating func remove(_ id: UUID) {
        ids.removeAll { $0 == id }
    }

    func contains(_ id: UUID) -> Bool {
        ids.contains(id)
    }
}
