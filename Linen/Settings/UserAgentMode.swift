// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

enum UserAgentMode: String, CaseIterable, Identifiable {
    case safari
    case linen = "Linen"
    case custom

    var id: String {
        rawValue
    }

    var label: LocalizedStringResource {
        switch self {
        case .safari:
            "Safari"
        case .linen:
            "Linen"
        case .custom:
            "Custom"
        }
    }
}
