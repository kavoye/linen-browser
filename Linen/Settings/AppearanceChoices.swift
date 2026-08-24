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

enum LoomStyle: String, CaseIterable, Identifiable {
    case standard
    case liquidGlass

    var id: String {
        rawValue
    }

    var label: LocalizedStringResource {
        switch self {
        case .standard:
            "Standard"
        case .liquidGlass:
            "Liquid Glass"
        }
    }
}
