// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import WebKit

struct ExtensionPageHost {
    let configuration: WKWebViewConfiguration
    let baseURL: URL
    let name: String
    let icon: NSImage?
}

enum PageSecurity: Equatable {
    case secure
    case pending
    case mixed
    case insecure
    case none
}

extension BrowserTab {
    enum InternalPage: String, Codable, CaseIterable {
        case history
        case downloads
        case releaseNotes
        case settings

        var title: String {
            switch self {
            case .settings:
                "Settings"
            case .history:
                "History"
            case .downloads:
                "Downloads"
            case .releaseNotes:
                "Release Notes"
            }
        }

        var symbol: String {
            switch self {
            case .settings:
                "gearshape"
            case .history:
                "clock"
            case .downloads:
                "arrow.down"
            case .releaseNotes:
                "doc.text"
            }
        }
    }
}

extension BrowserTab: Equatable {
    nonisolated static func == (lhs: BrowserTab, rhs: BrowserTab) -> Bool {
        lhs === rhs
    }
}
