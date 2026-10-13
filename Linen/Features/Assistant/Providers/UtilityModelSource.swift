// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel

@MainActor
enum UtilityModelSource {
    static var make: () -> (any LanguageModel)? = onDevice

    static var isAvailable: Bool {
        make() != nil
    }

    static let onDevice: () -> (any LanguageModel)? = {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        return SystemLanguageModel.default
    }
}
