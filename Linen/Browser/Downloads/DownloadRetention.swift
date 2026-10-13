// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Observation
import os
import WebKit

enum DownloadRetention: String, CaseIterable, Identifiable {
    case afterOneDay
    case onQuit
    case manually

    var id: String {
        rawValue
    }

    var label: LocalizedStringResource {
        switch self {
        case .afterOneDay:
            "After one day"
        case .onQuit:
            "When Linen quits"
        case .manually:
            "Manually"
        }
    }

    var maximumAge: TimeInterval? {
        self == .afterOneDay ? 86_400 : nil
    }
}
