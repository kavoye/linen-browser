// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum OpenAIProgressMessage {
    /// Decode the complete portion of updateProgress.message while its JSON arguments are still arriving.
    static func partial(_ arguments: String) -> String? {
        guard let key = arguments.range(of: #""message"\s*:\s*""#, options: .regularExpression) else { return nil }
        var raw = ""
        var escaped = false
        for character in arguments[key.upperBound...] {
            if escaped {
                raw.append(character)
                escaped = false
            } else if character == "\\" {
                raw.append(character)
                escaped = true
            } else if character == "\"" {
                break
            } else {
                raw.append(character)
            }
        }
        if escaped { raw.removeLast() }
        // A delta can stop halfway through a Unicode escape or surrogate pair.
        for _ in 0...12 {
            if let message = try? JSONDecoder().decode(String.self, from: Data(("\"" + raw + "\"").utf8)) {
                return message
            }
            guard !raw.isEmpty else { break }
            raw.removeLast()
        }
        return nil
    }
}
