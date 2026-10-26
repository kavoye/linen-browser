// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String {
        rawValue
    }

    var label: LocalizedStringResource {
        switch self {
        case .system:
            "Auto"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }
}

enum MinimalBarEdge: String, CaseIterable, Identifiable {
    case bottom
    case top

    var id: String {
        rawValue
    }

    var label: LocalizedStringResource {
        switch self {
        case .bottom:
            "Bottom"
        case .top:
            "Top"
        }
    }
}

enum MinimalBarHiding: String, CaseIterable, Identifiable {
    case never
    case whileScrolling
    case fiveSeconds
    case tenSeconds
    case thirtySeconds

    var id: String {
        rawValue
    }

    var label: LocalizedStringResource {
        switch self {
        case .never:
            LocalizedStringResource("settings.minimalBarHide.never", defaultValue: "Never")
        case .whileScrolling:
            LocalizedStringResource("settings.minimalBarHide.whileScrolling", defaultValue: "While scrolling")
        case .fiveSeconds:
            LocalizedStringResource("settings.minimalBarHide.fiveSeconds", defaultValue: "After 5 seconds")
        case .tenSeconds:
            LocalizedStringResource("settings.minimalBarHide.tenSeconds", defaultValue: "After 10 seconds")
        case .thirtySeconds:
            LocalizedStringResource("settings.minimalBarHide.thirtySeconds", defaultValue: "After 30 seconds")
        }
    }

    var interval: Duration? {
        switch self {
        case .never, .whileScrolling:
            nil
        case .fiveSeconds:
            .seconds(5)
        case .tenSeconds:
            .seconds(10)
        case .thirtySeconds:
            .seconds(30)
        }
    }
}

enum LoomStyle: String, CaseIterable, Identifiable {
    case standard
    case transparent

    var id: String {
        rawValue
    }

    var backgroundLabel: LocalizedStringResource {
        switch self {
        case .standard:
            "Solid"
        case .transparent:
            "Transparent"
        }
    }
}
