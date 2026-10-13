// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

@Observable
final class ChromeNotice {
    private(set) var text: String?
    private(set) var symbol: String?
    @ObservationIgnored private var token = 0

    func show(_ message: String, symbol: String? = nil) {
        text = message
        self.symbol = symbol
        token += 1
        let shown = token
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard token == shown else { return }
            text = nil
            self.symbol = nil
        }
    }
}
