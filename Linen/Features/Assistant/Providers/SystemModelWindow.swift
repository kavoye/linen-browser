// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import FoundationModels

nonisolated enum SystemModelWindow {
    static let tokens = SystemLanguageModel.default.contextSize
}
