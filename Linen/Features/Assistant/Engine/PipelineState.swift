// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

enum PipelineState: Equatable {
    case idle
    case listening
    case executing
}
