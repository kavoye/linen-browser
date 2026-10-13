// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

nonisolated enum AutoplayPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case allow
    case silent
    case block

    var id: String {
        rawValue
    }

    var label: LocalizedStringResource {
        switch self {
        case .allow:
            "Allow"
        case .silent:
            "Muted"
        case .block:
            "Never"
        }
    }

    var caption: LocalizedStringResource {
        switch self {
        case .allow:
            "Video and audio may start playing as soon as a page loads."
        case .silent:
            "Video plays without sound until you click."
        case .block:
            "Nothing plays until you press play."
        }
    }

    var mediaTypes: WKAudiovisualMediaTypes {
        switch self {
        case .allow:
            []
        case .silent:
            .audio
        case .block:
            .all
        }
    }
}
