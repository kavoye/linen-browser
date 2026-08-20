// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

nonisolated enum TabFolderColor: String, CaseIterable, Codable, Identifiable, Sendable {
    case gray
    case blue
    case purple
    case pink
    case red
    case orange
    case yellow
    case green
    case teal

    var id: Self {
        self
    }
}

@MainActor
@Observable
final class TabFolder: Identifiable {
    let id = UUID()
    var name: String
    var color = TabFolderColor.gray
    var isExpanded = true

    init(name: String) {
        self.name = name
    }
}

extension TabFolder: Equatable {
    nonisolated static func == (lhs: TabFolder, rhs: TabFolder) -> Bool {
        lhs === rhs
    }
}

nonisolated enum SidebarItem: Hashable, Identifiable, Sendable {
    case folder(UUID)
    case tab(UUID)

    var id: Self {
        self
    }
}
